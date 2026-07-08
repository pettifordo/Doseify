import Foundation
import DoseifyEngine

/// Bridges the pure V2 time-shift engine (`DoseifyEngine.DoseShiftEngine`)
/// into the app's trip scheduling.
///
/// The V2 engine handles exactly the case it was validated for: a twice-daily
/// medication shifting between two fixed timezone offsets, emitting a
/// symmetric ramp with every gap held at ~12h. Medications outside that shape
/// (once-daily, 3x, weekly schedules) keep the original `TimezoneShiftEngine`
/// results — this service only *overlays* V2 entries for eligible meds.
///
/// Known limitation inherited from V2 by design: fixed offsets, so a trip
/// window that crosses a DST transition can be off by an hour for the days
/// past the transition. Offsets are sampled at the outbound departure.
enum DoseShiftV2Service {

    /// V2 supports exactly two doses per day, every day.
    static func isEligible(_ med: Medication) -> Bool {
        med.scheduledTimesOfDay.count == 2 && med.scheduledDaysOfWeek.isEmpty
    }

    /// Rewrite a computed `TripSchedule` so eligible dose groups carry the V2
    /// engine's times. This is the single source of truth used by BOTH the
    /// dose-generation path (→ DoseEvents → notifications) and the trip
    /// preview screens, so what the app shows always equals what fires.
    ///
    /// A group is rewritten only when every member med is V2-eligible and all
    /// share the same two daily times (groups migrate in lockstep, so mixed
    /// groups keep the original engine). Manual overrides are never replaced.
    static func overlay(
        schedule: TripSchedule,
        trip: Trip,
        medications: [Medication],
        settings: UserSettings
    ) -> TripSchedule {
        let v2 = entries(trip: trip, medications: medications, settings: settings)
        guard !v2.isEmpty else { return schedule }
        let medsByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })

        let groups = schedule.doseGroups.map { group -> DoseGroupSchedule in
            let groupMeds = group.medicationIDs.compactMap { medsByID[$0] }
            guard !groupMeds.isEmpty,
                  groupMeds.allSatisfy(isEligible),
                  Set(groupMeds.map { $0.scheduledTimesOfDay.sorted() }).count == 1,
                  let rep = groupMeds.first else { return group }

            let newEntries = group.entries.map { entry -> ScheduledDose in
                guard !entry.isManualOverride,
                      let v = v2["\(rep.id)-\(entry.scheduledTimeHomeUTC.timeIntervalSince1970)"]
                else { return entry }
                return v
            }
            return DoseGroupSchedule(
                groupId: group.groupId, medicationIDs: group.medicationIDs, entries: newEntries
            )
        }
        return TripSchedule(doseGroups: groups, warnings: schedule.warnings, summary: schedule.summary)
    }

    /// Compute V2 shift entries for every eligible medication on this trip,
    /// keyed `"\(medID)-\(scheduledTimeHomeUTC.timeIntervalSince1970)"` — the
    /// same key format `MedicationStore.generateUpcomingDoses` matches on.
    static func entries(
        trip: Trip,
        medications: [Medication],
        settings: UserSettings
    ) -> [String: ScheduledDose] {
        guard let outbound = trip.outboundFlight, let ret = trip.returnFlight else { return [:] }
        guard let homeTZ = TimeZone(identifier: settings.homeTimezone),
              let destTZ = TimeZone(identifier: trip.destinationTimezone) else { return [:] }

        let homeOff = Double(homeTZ.secondsFromGMT(for: outbound.departureDateTime)) / 3600
        let destOff = Double(destTZ.secondsFromGMT(for: outbound.arrivalDateTime)) / 3600

        var lookup: [String: ScheduledDose] = [:]

        for med in medications where isEligible(med) {
            let times = med.scheduledTimesOfDay.sorted()
            let morning = times[0]
            let evening = times[1]

            let step = med.timezoneShiftMinutesPerDay > 0 ? med.timezoneShiftMinutesPerDay : 30

            // Direction/target — same selection the engine makes internally;
            // needed here to recover scheduledTimeHome from each emitted dose
            // and to size the pre-shift window.
            let gapHr = Double(evening.totalMinutes - morning.totalMinutes) / 60
            let shiftHr = destOff - homeOff
            let absShift = abs(shiftHr)
            var direction: Double = 0
            var targetShiftHr: Double = 0
            if absShift > 0 {
                if absShift <= gapHr / 2 {
                    direction = shiftHr > 0 ? -1 : 1
                    targetShiftHr = absShift
                } else {
                    direction = shiftHr > 0 ? 1 : -1
                    targetShiftHr = max(0, 24 - gapHr - absShift)
                }
            }
            let stepHr = Double(step) / 60
            let preShiftDays = trip.preShiftEnabled && stepHr > 0
                ? Int(ceil(targetShiftHr / stepHr))
                : 0

            let input = ScheduleInput(
                homeOffsetHours: homeOff,
                destOffsetHours: destOff,
                departureUTC: outbound.departureDateTime,
                arrivalUTC: outbound.arrivalDateTime,
                returnDepartureUTC: ret.departureDateTime,
                returnArrivalUTC: ret.arrivalDateTime,
                morningTime: DateComponents(hour: morning.hour, minute: morning.minute),
                eveningTime: DateComponents(hour: evening.hour, minute: evening.minute),
                preShiftDays: preShiftDays,
                stepMinutes: step,
                medName: med.name
            )

            guard let doses = try? DoseShiftEngine.generateDoses(input: input) else { continue }

            for dose in doses {
                // The engine emitted utc = homeAnchor + accumulatedShift*direction,
                // so the sacred home-anchored time is recovered by removing it.
                let shiftSeconds = Double(dose.accumulatedShiftMinutes) * 60 * direction
                // Round to whole seconds so the key matches the store's exact
                // `tod.date(on:in:)` epoch despite Double arithmetic.
                let scheduledHome = Date(
                    timeIntervalSince1970: (dose.utc.timeIntervalSince1970 - shiftSeconds).rounded()
                )

                let atDestination = dose.utc >= outbound.arrivalDateTime
                    && dose.utc < ret.departureDateTime
                let context: LocationContext = dose.utc < outbound.departureDateTime
                    ? (dose.accumulatedShiftMinutes == 0 ? .home : .preShifting)
                    : (atDestination ? .destinationShifting
                        : (dose.utc >= ret.arrivalDateTime ? .postReturn : .inFlightOutbound))

                let entry = ScheduledDose(
                    scheduledTimeHomeUTC: scheduledHome,
                    day: DoseShiftEngine.startOfDayInFrame(
                        scheduledHome.timeIntervalSince1970, offsetHours: homeOff
                    ).asDate,
                    effectiveTimeUTC: dose.utc,
                    effectiveTimezone: atDestination ? trip.destinationTimezone : settings.homeTimezone,
                    context: context,
                    badge: dose.accumulatedShiftMinutes == 0 ? .stable : .shifting,
                    isManualOverride: false,
                    isSkipped: false
                )
                lookup["\(med.id)-\(scheduledHome.timeIntervalSince1970)"] = entry
            }
        }
        return lookup
    }
}

private extension TimeInterval {
    var asDate: Date { Date(timeIntervalSince1970: self) }
}
