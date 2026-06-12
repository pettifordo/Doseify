import Foundation

/// A small library of common CLL-related medication templates the user can
/// optionally add during setup, so they don't have to fill in every field
/// from scratch for well-known drugs.
///
/// These are starting points only — names, dosing windows, and schedules
/// are editable/deletable like any other medication, and no dose history
/// or inventory is fabricated. Nothing here is medical advice; the user
/// (or their care team) is responsible for the actual prescribed regimen.
enum ExampleMedicationLibrary {

    struct Template: Identifiable {
        let id = UUID()
        let name: String
        let summary: String
        let colorHex: String
        let doseAmount: Double
        let doseUnit: String
        let scheduledDaysOfWeek: [Int]
        let scheduledTimesOfDay: [TimeOfDay]
        let withFood: Bool
        let onTimeWindowMinutes: Int
        let cutoffMinutes: Int
        let preAlertMinutes: Int
        let timezoneShiftMinutesPerDay: Int
        let notes: String?

        func makeMedication() -> Medication {
            let med = Medication(
                name: name,
                colorHex: colorHex,
                doseAmount: doseAmount,
                doseUnit: doseUnit,
                scheduledDaysOfWeek: scheduledDaysOfWeek,
                scheduledTimesOfDay: scheduledTimesOfDay,
                withFood: withFood,
                onTimeWindowMinutes: onTimeWindowMinutes,
                cutoffMinutes: cutoffMinutes,
                preAlertMinutes: preAlertMinutes,
                timezoneShiftMinutesPerDay: timezoneShiftMinutesPerDay,
                inventoryCount: 0,
                refillThresholdDays: 7
            )
            med.notes = notes
            return med
        }
    }

    static let all: [Template] = [
        Template(
            name: "Acalabrutinib",
            summary: "BTK inhibitor — twice daily, ~12 hours apart",
            colorHex: "#7B9E87",
            doseAmount: 1,
            doseUnit: "capsule",
            scheduledDaysOfWeek: [],   // every day
            scheduledTimesOfDay: [
                TimeOfDay(hour: 8, minute: 0),
                TimeOfDay(hour: 20, minute: 0),
            ],
            withFood: false,
            onTimeWindowMinutes: 30,
            cutoffMinutes: 120,
            preAlertMinutes: 10,
            timezoneShiftMinutesPerDay: 30,
            notes: "Take roughly 12 hours apart, with or without food."
        ),
        Template(
            name: "Acyclovir",
            summary: "Antiviral prophylaxis — twice daily, with food",
            colorHex: "#7B9DD8",
            doseAmount: 1,
            doseUnit: "tablet",
            scheduledDaysOfWeek: [],   // every day
            scheduledTimesOfDay: [
                TimeOfDay(hour: 8, minute: 0),
                TimeOfDay(hour: 20, minute: 0),
            ],
            withFood: true,
            onTimeWindowMinutes: 60,
            cutoffMinutes: 180,
            preAlertMinutes: 10,
            timezoneShiftMinutesPerDay: 30,
            notes: "Antiviral prophylaxis (shingles/HSV prevention)."
        ),
        Template(
            name: "Co-trimoxazole",
            summary: "Antibiotic prophylaxis — Mon/Wed/Fri, with food",
            colorHex: "#F2C4A4",
            doseAmount: 1,
            doseUnit: "tablet",
            scheduledDaysOfWeek: [1, 3, 5],   // Mon / Wed / Fri
            scheduledTimesOfDay: [
                TimeOfDay(hour: 9, minute: 0),
            ],
            withFood: true,
            onTimeWindowMinutes: 60,
            cutoffMinutes: 240,
            preAlertMinutes: 10,
            timezoneShiftMinutesPerDay: 30,
            notes: "Antibiotic prophylaxis (PJP prevention) — Mon/Wed/Fri."
        ),
    ]
}
