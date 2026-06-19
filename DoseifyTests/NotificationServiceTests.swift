import Testing
import Foundation
@testable import Doseify

@Suite("NotificationService")
struct NotificationServiceTests {

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)) ?? .distantPast
    }

    @Test("Sleep window is evaluated in the dose's own timezone")
    func sleepWindowRespectsTimezone() {
        let settings = UserSettings()   // default window 00:00–06:00

        // 03:00 UTC is inside the window when read in UTC…
        #expect(NotificationService.isInSleepWindow(utc(2025, 1, 1, 3), timezoneID: "UTC", settings: settings))
        // …but the same instant is midday in Tokyo (UTC+9) → outside.
        #expect(!NotificationService.isInSleepWindow(utc(2025, 1, 1, 3), timezoneID: "Asia/Tokyo", settings: settings))
        // 08:00 local is clearly outside.
        #expect(!NotificationService.isInSleepWindow(utc(2025, 1, 1, 8), timezoneID: "UTC", settings: settings))
    }

    @Test("A window that wraps past midnight is handled")
    func sleepWindowWrapsMidnight() {
        let settings = UserSettings()
        settings.sleepWindowStart = TimeOfDay(hour: 22, minute: 0)
        settings.sleepWindowEnd = TimeOfDay(hour: 6, minute: 0)
        #expect(NotificationService.isInSleepWindow(utc(2025, 1, 1, 23), timezoneID: "UTC", settings: settings))  // 23:00
        #expect(NotificationService.isInSleepWindow(utc(2025, 1, 1, 2), timezoneID: "UTC", settings: settings))   // 02:00
        #expect(!NotificationService.isInSleepWindow(utc(2025, 1, 1, 12), timezoneID: "UTC", settings: settings)) // noon
    }
}
