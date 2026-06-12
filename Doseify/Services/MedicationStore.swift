import Foundation
import SwiftData

/// SwiftData CRUD wrapper. All mutations go through here so side-effects
/// (notification reschedule, HealthKit write) can be triggered in one place.
@MainActor
final class MedicationStore: ObservableObject {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch

    func allMedications() throws -> [Medication] {
        let descriptor = FetchDescriptor<Medication>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func activeMedications() throws -> [Medication] {
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func settings() throws -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()
        let all = try modelContext.fetch(descriptor)
        if let s = all.first { return s }
        let s = UserSettings()
        modelContext.insert(s)
        try modelContext.save()
        return s
    }

    /// The trip relevant to dose scheduling right now: an active trip, or the
    /// soonest upcoming planned trip that hasn't ended yet. A planned trip is
    /// returned even before its `startDate` so a pre-trip ramp (see
    /// `TimezoneShiftEngine`) can begin adjusting upcoming doses ahead of departure.
    func activeTrip(now: Date = Date()) throws -> Trip? {
        let descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate)])
        let trips = try modelContext.fetch(descriptor)
        if let active = trips.first(where: { $0.status == .active }) {
            return active
        }
        return trips.first { trip in
            trip.status == .planned && trip.endDate >= now
        }
    }

    func allTrips() throws -> [Trip] {
        let descriptor = FetchDescriptor<Trip>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Medication CRUD

    func addMedication(_ medication: Medication) throws {
        modelContext.insert(medication)
        try modelContext.save()
    }

    func deleteMedication(_ medication: Medication) throws {
        modelContext.delete(medication)
        try modelContext.save()
    }

    func save() throws {
        try modelContext.save()
    }

    // MARK: - Dose events

    /// Generate pending DoseEvent records for the coming `days` days for all active medications.
    func generateUpcomingDoses(days: Int = 7, settings: UserSettings) throws {
        let meds = try activeMedications()
        let homeTZ = TimeZone(identifier: settings.homeTimezone) ?? .current
        let trip = try activeTrip()
        let now = Date()
        let cal = Calendar(identifier: .gregorian)

        // Build the trip's shift lookup once (if a trip is in play). Maps
        // (medicationID, home-anchored UTC instant) → the engine's computed dose.
        var shiftLookup: [String: ScheduledDose] = [:]
        if let trip = trip {
            let overrides = try modelContext.fetch(FetchDescriptor<DoseOverride>())
                .filter { $0.tripId == trip.id }
            let schedule = TimezoneShiftEngine.computeTrip(
                trip: trip, medications: meds, userSettings: settings, existingOverrides: overrides
            )
            for group in schedule.doseGroups {
                for entry in group.entries {
                    for medID in group.medicationIDs {
                        shiftLookup["\(medID)-\(entry.scheduledTimeHomeUTC.timeIntervalSince1970)"] = entry
                    }
                }
            }
        }

        // Fetch all existing doses once; de-dupe in memory (avoids #Predicate in a tight loop).
        let allExisting = try modelContext.fetch(FetchDescriptor<DoseEvent>())
        var existingKeys = Set<String>()
        for d in allExisting {
            if let medID = d.medication?.id {
                existingKeys.insert("\(medID)-\(d.scheduledTimeHome.timeIntervalSince1970)")
            }
        }

        for med in meds {
            for dayOffset in 0..<days {
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                let isoWeekday = isoWeekday(from: day, cal: cal)
                guard med.isScheduled(on: isoWeekday) else { continue }

                for tod in med.scheduledTimesOfDay {
                    let homeDate = tod.date(on: day, in: homeTZ)
                    let key = "\(med.id)-\(homeDate.timeIntervalSince1970)"
                    guard !existingKeys.contains(key) else { continue }
                    existingKeys.insert(key)

                    let entry = shiftLookup[key]
                    let effectiveDate = entry?.effectiveTimeUTC ?? homeDate
                    let tzID = entry?.effectiveTimezone ?? settings.homeTimezone

                    let dose = DoseEvent(
                        medication: med,
                        scheduledTimeHome: homeDate,
                        effectiveScheduledTime: effectiveDate,
                        effectiveTimezone: tzID
                    )
                    if let entry = entry, entry.isManualOverride {
                        dose.overrideAppliedId = dose.id
                    }
                    // A dose the travel engine skips for overdose protection is
                    // recorded as skipped (no reminder, no streak penalty).
                    if entry?.isSkipped == true {
                        dose.status = .skipped
                    }
                    modelContext.insert(dose)
                }
            }
        }
        try modelContext.save()
    }

    /// Log a dose as taken at the given time.
    func logDose(_ dose: DoseEvent, at time: Date = Date()) throws {
        guard let med = dose.medication else { return }
        dose.loggedTime = time
        dose.status = .taken
        dose.score = DoseScorer.score(
            scheduledTime: dose.effectiveScheduledTime,
            loggedTime: time,
            onTimeWindowMinutes: med.onTimeWindowMinutes,
            cutoffMinutes: med.cutoffMinutes
        )
        if med.inventoryCount > 0 {
            med.inventoryCount -= 1
        }
        try modelContext.save()
        // Note: Apple Health exposes no API to write medication dose events, so
        // there is no HealthKit write here (see HealthKitGateway). Import is read-only.
    }

    /// Log several doses as taken at once (e.g. "take all due at 8:00").
    /// Only pending/missed doses are affected; already-recorded doses are left alone.
    /// Returns the doses actually logged so the caller can cancel their follow-ups.
    @discardableResult
    func logDoses(_ doses: [DoseEvent], at time: Date = Date()) throws -> [DoseEvent] {
        let loggable = doses.filter { $0.status == .pending || $0.status == .missed }
        for dose in loggable {
            try logDose(dose, at: time)
        }
        return loggable
    }

    /// Skip a dose.
    func skipDose(_ dose: DoseEvent) throws {
        dose.status = .skipped
        try modelContext.save()
    }

    /// Skip several pending doses at once.
    func skipDoses(_ doses: [DoseEvent]) throws {
        for dose in doses where dose.status == .pending {
            dose.status = .skipped
        }
        try modelContext.save()
    }

    /// Find the DoseEvent matching a medication and its home-anchored scheduled time.
    /// Used to resolve notification action taps back to the originating dose.
    /// Tolerance accounts for Date round-tripping through Double in notification userInfo.
    func findDose(medicationID: UUID, scheduledTimeHome: Date) throws -> DoseEvent? {
        let all = try modelContext.fetch(FetchDescriptor<DoseEvent>())
        return all.first {
            $0.medication?.id == medicationID &&
            abs($0.scheduledTimeHome.timeIntervalSince(scheduledTimeHome)) < 1
        }
    }

    /// Mark pending doses past their cutoff as missed.
    func rolloverMissedDoses(settings: UserSettings) throws {
        // Fetch all and filter in memory — SwiftData #Predicate can't compare enum rawValues.
        let all = try modelContext.fetch(FetchDescriptor<DoseEvent>())
        let pending = all.filter { $0.status == .pending }
        let now = Date()
        for dose in pending {
            guard let med = dose.medication else { continue }
            let newStatus = DoseScorer.pendingStatus(
                effectiveScheduledTime: dose.effectiveScheduledTime,
                now: now,
                cutoffMinutes: med.cutoffMinutes
            )
            if newStatus == .missed {
                dose.status = .missed
            }
        }
        try modelContext.save()
    }

    // MARK: - Trip CRUD

    func addTrip(_ trip: Trip) throws {
        modelContext.insert(trip)
        try modelContext.save()
    }

    func deleteTrip(_ trip: Trip) throws {
        modelContext.delete(trip)
        try modelContext.save()
    }

    // MARK: - Side effect log

    func logSideEffect(_ log: SideEffectLog) throws {
        modelContext.insert(log)
        try modelContext.save()
    }

    // MARK: - Helpers

    private func isoWeekday(from date: Date, cal: Calendar) -> Int {
        let w = cal.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }
}
