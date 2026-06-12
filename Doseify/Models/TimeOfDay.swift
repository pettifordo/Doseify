import Foundation

struct TimeOfDay: Codable, Hashable, Comparable {
    var hour: Int   // 0–23
    var minute: Int // 0–59

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
        return lhs.minute < rhs.minute
    }

    var displayString: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let m = String(format: "%02d", minute)
        let period = hour < 12 ? "AM" : "PM"
        return "\(h):\(m) \(period)"
    }

    var totalMinutes: Int { hour * 60 + minute }

    /// Build a `TimeOfDay` from minutes past local midnight, wrapping into 0..<1440.
    init(minutesFromMidnight: Int) {
        let m = ((minutesFromMidnight % 1440) + 1440) % 1440
        self.hour = m / 60
        self.minute = m % 60
    }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    func date(on referenceDate: Date, in timezone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        var comps = cal.dateComponents([.year, .month, .day], from: referenceDate)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return cal.date(from: comps) ?? referenceDate
    }

    static let morning = TimeOfDay(hour: 8, minute: 0)
    static let noon = TimeOfDay(hour: 12, minute: 0)
    static let evening = TimeOfDay(hour: 20, minute: 0)
}
