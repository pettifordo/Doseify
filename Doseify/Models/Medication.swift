import Foundation
import SwiftData

@Model
final class Medication {
    var id: UUID
    var name: String
    var colorHex: String
    var iconName: String?
    var pillPhoto: Data?
    var doseAmount: Double
    var doseUnit: String
    var withFood: Bool
    var onTimeWindowMinutes: Int
    var cutoffMinutes: Int
    var preAlertMinutes: Int
    var timezoneShiftMinutesPerDay: Int
    var shiftDirectionPreference: ShiftDirectionPreference
    /// Drugs sharing a `shiftGroupId` migrate in lockstep; nil = independent (SPEC §2.4.1).
    var shiftGroupId: UUID?
    /// Minimum hours between doses for BID/TID drugs, maintained across shifts (SPEC §2.4.8 case 7).
    var minSpacingHours: Int
    var inventoryCount: Int
    var refillThresholdDays: Int
    var isCriticalAlert: Bool
    var notes: String?
    var isActive: Bool
    var createdAt: Date

    // Stored as Codable — SwiftData encodes [TimeOfDay] and [Int] automatically
    var scheduledDaysOfWeek: [Int]         // ISO 1..7, empty = daily
    var scheduledTimesOfDay: [TimeOfDay]

    @Relationship(deleteRule: .cascade, inverse: \DoseEvent.medication)
    var doses: [DoseEvent] = []

    // Pharmacy info (stored only, v1 display TBD)
    var pharmacyName: String?
    var pharmacyPhone: String?

    init(
        name: String,
        colorHex: String = "#7B9E87",
        doseAmount: Double = 1,
        doseUnit: String = "capsule",
        scheduledDaysOfWeek: [Int] = [],
        scheduledTimesOfDay: [TimeOfDay] = [.morning],
        withFood: Bool = false,
        onTimeWindowMinutes: Int = 5,
        cutoffMinutes: Int = 120,
        preAlertMinutes: Int = 10,
        timezoneShiftMinutesPerDay: Int = 30,
        shiftDirectionPreference: ShiftDirectionPreference = .smart,
        shiftGroupId: UUID? = nil,
        minSpacingHours: Int = 11,
        inventoryCount: Int = 0,
        refillThresholdDays: Int = 7
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.doseAmount = doseAmount
        self.doseUnit = doseUnit
        self.scheduledDaysOfWeek = scheduledDaysOfWeek
        self.scheduledTimesOfDay = scheduledTimesOfDay
        self.withFood = withFood
        self.onTimeWindowMinutes = onTimeWindowMinutes
        self.cutoffMinutes = cutoffMinutes
        self.preAlertMinutes = preAlertMinutes
        self.timezoneShiftMinutesPerDay = timezoneShiftMinutesPerDay
        self.shiftDirectionPreference = shiftDirectionPreference
        self.shiftGroupId = shiftGroupId
        self.minSpacingHours = minSpacingHours
        self.inventoryCount = inventoryCount
        self.refillThresholdDays = refillThresholdDays
        self.isCriticalAlert = false
        self.isActive = true
        self.createdAt = Date()
    }

    // MARK: - Helpers

    var dosesPerDay: Int {
        let days = scheduledDaysOfWeek.isEmpty ? 7 : scheduledDaysOfWeek.count
        return scheduledTimesOfDay.count * (days > 0 ? 1 : 0)
    }

    var refillThresholdCount: Int {
        max(1, refillThresholdDays * scheduledTimesOfDay.count)
    }

    var needsRefill: Bool {
        inventoryCount <= refillThresholdCount
    }

    /// Whole days of supply left at the current schedule, or nil if the schedule
    /// has no doses (can't estimate).
    var daysOfSupplyRemaining: Int? {
        dosesPerDay > 0 ? inventoryCount / dosesPerDay : nil
    }

    /// True only when the user is actually tracking stock (count > 0) and it has
    /// dropped to/below the refill threshold — avoids false alarms for the common
    /// case of an untracked medication left at 0.
    var isLowOnSupply: Bool {
        inventoryCount > 0 && needsRefill
    }

    /// Short human label for remaining supply, e.g. "3 days left · 6 left".
    var supplyRemainingLabel: String {
        if let days = daysOfSupplyRemaining {
            return "\(days) day\(days == 1 ? "" : "s") left · \(inventoryCount) left"
        }
        return "\(inventoryCount) left"
    }

    func isScheduled(on weekday: Int) -> Bool {
        scheduledDaysOfWeek.isEmpty || scheduledDaysOfWeek.contains(weekday)
    }
}
