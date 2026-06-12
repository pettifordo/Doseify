import Foundation
import SwiftData

@Model
final class UserSettings {
    var homeTimezone: String
    var autoDetectTimezone: Bool

    // Sleep / forbidden window — no dose is scheduled inside it (SPEC §2.4.1).
    // Default 00:00–06:00 local. Stored as components for SwiftData friendliness.
    var sleepWindowStartHour: Int
    var sleepWindowStartMinute: Int
    var sleepWindowEndHour: Int
    var sleepWindowEndMinute: Int

    // Quiet hours are separate from the sleep window — they suppress escalating
    // notifications only (SPEC §2.4 / §2.2), and do not affect dose scheduling.
    var quietHoursStartHour: Int?
    var quietHoursStartMinute: Int?
    var quietHoursEndHour: Int?
    var quietHoursEndMinute: Int?
    var theme: AppTheme

    init(homeTimezone: String = TimeZone.current.identifier) {
        self.homeTimezone = homeTimezone
        self.autoDetectTimezone = true
        self.sleepWindowStartHour = 0
        self.sleepWindowStartMinute = 0
        self.sleepWindowEndHour = 6
        self.sleepWindowEndMinute = 0
        self.theme = .system
    }

    var sleepWindowStart: TimeOfDay {
        get { TimeOfDay(hour: sleepWindowStartHour, minute: sleepWindowStartMinute) }
        set { sleepWindowStartHour = newValue.hour; sleepWindowStartMinute = newValue.minute }
    }

    var sleepWindowEnd: TimeOfDay {
        get { TimeOfDay(hour: sleepWindowEndHour, minute: sleepWindowEndMinute) }
        set { sleepWindowEndHour = newValue.hour; sleepWindowEndMinute = newValue.minute }
    }

    var quietHoursStart: TimeOfDay? {
        get {
            guard let h = quietHoursStartHour, let m = quietHoursStartMinute else { return nil }
            return TimeOfDay(hour: h, minute: m)
        }
        set {
            quietHoursStartHour = newValue?.hour
            quietHoursStartMinute = newValue?.minute
        }
    }

    var quietHoursEnd: TimeOfDay? {
        get {
            guard let h = quietHoursEndHour, let m = quietHoursEndMinute else { return nil }
            return TimeOfDay(hour: h, minute: m)
        }
        set {
            quietHoursEndHour = newValue?.hour
            quietHoursEndMinute = newValue?.minute
        }
    }
}
