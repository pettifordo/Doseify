import Foundation
import SwiftData

#if DEBUG
/// Populates the store with realistic demo data — for App Store screenshots
/// and UI development only. Compiled out entirely in Release builds.
enum DebugSeeder {

    /// Seeds demo medications, today's doses, and recent history,
    /// but only if the store is currently empty (never overwrites real data).
    static func seedIfNeeded(modelContext: ModelContext) {
        let existing = try? modelContext.fetch(FetchDescriptor<Medication>())
        guard existing?.isEmpty ?? true else { return }

        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        // MARK: - Medications

        // Primary CLL treatment
        let acalabrutinib = Medication(
            name: "Acalabrutinib",
            colorHex: "#7B9E87",
            doseAmount: 1,
            doseUnit: "capsule",
            scheduledDaysOfWeek: [],   // every day
            scheduledTimesOfDay: [
                TimeOfDay(hour: 8, minute: 0),
                TimeOfDay(hour: 20, minute: 0)
            ],
            withFood: false,
            onTimeWindowMinutes: 30,
            cutoffMinutes: 120,
            preAlertMinutes: 10,
            timezoneShiftMinutesPerDay: 30,
            inventoryCount: 42,
            refillThresholdDays: 7
        )
        acalabrutinib.notes = "Take roughly 12 hours apart, with or without food."

        // Antiviral prophylaxis (common alongside BTK inhibitors)
        let acyclovir = Medication(
            name: "Acyclovir",
            colorHex: "#7B9DD8",
            doseAmount: 1,
            doseUnit: "tablet",
            scheduledDaysOfWeek: [],   // every day
            scheduledTimesOfDay: [
                TimeOfDay(hour: 8, minute: 0),
                TimeOfDay(hour: 20, minute: 0)
            ],
            withFood: true,
            onTimeWindowMinutes: 60,
            cutoffMinutes: 180,
            preAlertMinutes: 10,
            timezoneShiftMinutesPerDay: 30,
            inventoryCount: 28,
            refillThresholdDays: 5
        )
        acyclovir.notes = "Antiviral prophylaxis (shingles/HSV prevention)."

        // Antibiotic prophylaxis (e.g. co-trimoxazole, common for PJP prevention)
        let cotrimoxazole = Medication(
            name: "Co-trimoxazole",
            colorHex: "#F2C4A4",
            doseAmount: 1,
            doseUnit: "tablet",
            scheduledDaysOfWeek: [1, 3, 5],   // Mon / Wed / Fri
            scheduledTimesOfDay: [
                TimeOfDay(hour: 9, minute: 0)
            ],
            withFood: true,
            onTimeWindowMinutes: 60,
            cutoffMinutes: 240,
            preAlertMinutes: 10,
            timezoneShiftMinutesPerDay: 30,
            inventoryCount: 9,
            refillThresholdDays: 7
        )
        cotrimoxazole.notes = "Antibiotic prophylaxis (PJP prevention) — Mon/Wed/Fri."
        cotrimoxazole.pharmacyName = "Boots Pharmacy"
        cotrimoxazole.pharmacyPhone = "01234 567890"

        for med in [acalabrutinib, acyclovir, cotrimoxazole] {
            modelContext.insert(med)
        }

        // MARK: - Dose history (last 13 days, mostly taken — for a streak)

        for med in [acalabrutinib, acyclovir, cotrimoxazole] {
            for dayOffset in stride(from: -13, through: -1, by: 1) {
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
                let isoWeekday = isoWeekday(from: day, cal: cal)
                guard med.isScheduled(on: isoWeekday) else { continue }

                for tod in med.scheduledTimesOfDay {
                    let scheduled = tod.date(on: day, in: .current)
                    let dose = DoseEvent(
                        medication: med,
                        scheduledTimeHome: scheduled,
                        effectiveScheduledTime: scheduled,
                        effectiveTimezone: TimeZone.current.identifier
                    )
                    // Log most doses as taken, right on time
                    let loggedTime = scheduled.addingTimeInterval(Double.random(in: -5...10) * 60)
                    dose.loggedTime = loggedTime
                    dose.status = .taken
                    dose.score = DoseScorer.score(
                        scheduledTime: scheduled,
                        loggedTime: loggedTime,
                        onTimeWindowMinutes: med.onTimeWindowMinutes,
                        cutoffMinutes: med.cutoffMinutes
                    )
                    modelContext.insert(dose)
                }
            }
        }

        // MARK: - Today's doses (mixed states for a realistic Today screen)

        // Acalabrutinib — morning dose already taken
        if let amTime = acalabrutinib.scheduledTimesOfDay.first {
            let scheduled = amTime.date(on: today, in: .current)
            let dose = DoseEvent(
                medication: acalabrutinib,
                scheduledTimeHome: scheduled,
                effectiveScheduledTime: scheduled,
                effectiveTimezone: TimeZone.current.identifier
            )
            let loggedTime = scheduled.addingTimeInterval(4 * 60)
            dose.loggedTime = loggedTime
            dose.status = .taken
            dose.score = DoseScorer.score(
                scheduledTime: scheduled,
                loggedTime: loggedTime,
                onTimeWindowMinutes: acalabrutinib.onTimeWindowMinutes,
                cutoffMinutes: acalabrutinib.cutoffMinutes
            )
            modelContext.insert(dose)
        }

        // Acalabrutinib — evening dose still pending (upcoming)
        if acalabrutinib.scheduledTimesOfDay.count > 1 {
            let pmTime = acalabrutinib.scheduledTimesOfDay[1]
            let scheduled = pmTime.date(on: today, in: .current)
            let dose = DoseEvent(
                medication: acalabrutinib,
                scheduledTimeHome: scheduled,
                effectiveScheduledTime: scheduled,
                effectiveTimezone: TimeZone.current.identifier
            )
            modelContext.insert(dose)
        }

        // Acyclovir — morning dose taken
        if let amTime = acyclovir.scheduledTimesOfDay.first {
            let scheduled = amTime.date(on: today, in: .current)
            let dose = DoseEvent(
                medication: acyclovir,
                scheduledTimeHome: scheduled,
                effectiveScheduledTime: scheduled,
                effectiveTimezone: TimeZone.current.identifier
            )
            let loggedTime = scheduled.addingTimeInterval(2 * 60)
            dose.loggedTime = loggedTime
            dose.status = .taken
            dose.score = DoseScorer.score(
                scheduledTime: scheduled,
                loggedTime: loggedTime,
                onTimeWindowMinutes: acyclovir.onTimeWindowMinutes,
                cutoffMinutes: acyclovir.cutoffMinutes
            )
            modelContext.insert(dose)
        }

        // Acyclovir — evening dose pending
        if acyclovir.scheduledTimesOfDay.count > 1 {
            let pmTime = acyclovir.scheduledTimesOfDay[1]
            let scheduled = pmTime.date(on: today, in: .current)
            let dose = DoseEvent(
                medication: acyclovir,
                scheduledTimeHome: scheduled,
                effectiveScheduledTime: scheduled,
                effectiveTimezone: TimeZone.current.identifier
            )
            modelContext.insert(dose)
        }

        // Co-trimoxazole — only on Mon/Wed/Fri; add today's dose if scheduled
        let todayISO = isoWeekday(from: today, cal: cal)
        if cotrimoxazole.isScheduled(on: todayISO), let tod = cotrimoxazole.scheduledTimesOfDay.first {
            let scheduled = tod.date(on: today, in: .current)
            let dose = DoseEvent(
                medication: cotrimoxazole,
                scheduledTimeHome: scheduled,
                effectiveScheduledTime: scheduled,
                effectiveTimezone: TimeZone.current.identifier
            )
            // If scheduled time has already passed, mark as missed for variety
            if scheduled < now.addingTimeInterval(-Double(cotrimoxazole.cutoffMinutes) * 60) {
                dose.status = .missed
            }
            modelContext.insert(dose)
        }

        try? modelContext.save()
    }

    // MARK: - Helpers

    private static func isoWeekday(from date: Date, cal: Calendar) -> Int {
        let w = cal.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }
}
#endif
