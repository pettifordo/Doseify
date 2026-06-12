import Foundation
import UserNotifications

/// Manages the UNUserNotificationCenter queue.
/// iOS caps at 64 pending notifications — we schedule the next N eagerly.
@MainActor
final class NotificationService: ObservableObject {

    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    // MARK: - Notification category identifiers
    static let categoryDose = "DOSE_REMINDER"
    static let actionTaken  = "TAKEN_NOW"
    static let actionSnooze = "SNOOZE_5"
    static let actionSkip   = "SKIP_DOSE"

    // MARK: - Request permission

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted { registerCategories() }
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Category registration

    private func registerCategories() {
        let takenAction  = UNNotificationAction(identifier: Self.actionTaken,  title: "Taken now",   options: [.foreground])
        let snoozeAction = UNNotificationAction(identifier: Self.actionSnooze, title: "Snooze 5 min", options: [])
        let skipAction   = UNNotificationAction(identifier: Self.actionSkip,   title: "Skip dose",   options: [.destructive])

        let category = UNNotificationCategory(
            identifier: Self.categoryDose,
            actions: [takenAction, snoozeAction, skipAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - Schedule notifications across all medications

    /// Rebuild the pending-notification queue for **all** active medications at once.
    ///
    /// iOS keeps at most 64 pending notifications, and each dose needs up to five
    /// of them (pre-alert, at-time, and +5/+15/+30 follow-ups). Scheduling each
    /// medication independently let the first one consume the whole budget and
    /// starve the rest — so only one medication ever fired. Instead we gather every
    /// upcoming dose across all medications, order them soonest-first, and fill a
    /// single shared budget, so the *next* reminders for every medication are
    /// scheduled before the cap is reached. The window is rebuilt on each launch
    /// and on any schedule change, so it rolls forward over time.
    func rescheduleAll(for medications: [Medication], settings: UserSettings, upcomingDays: Int = 7) async {
        await removeAllDoseNotifications()

        let homeTZ = TimeZone(identifier: settings.homeTimezone) ?? .current
        let now = Date()

        struct Occurrence { let med: Medication; let fireDate: Date }
        var occurrences: [Occurrence] = []
        for med in medications where med.isActive {
            for dayOffset in 0..<upcomingDays {
                guard let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                guard med.isScheduled(on: isoWeekday(from: day)) else { continue }
                for tod in med.scheduledTimesOfDay {
                    let fireDate = tod.date(on: day, in: homeTZ)
                    if fireDate > now { occurrences.append(Occurrence(med: med, fireDate: fireDate)) }
                }
            }
        }
        // Soonest first, so every medication's nearest doses are scheduled before
        // the shared budget runs out (this is what fixes "only one med fires").
        occurrences.sort { $0.fireDate < $1.fireDate }

        // Stay under iOS's 64-pending cap, leaving headroom for snooze reminders.
        let budget = 60
        var used = 0

        for occ in occurrences {
            if used >= budget { break }
            let med = occ.med
            let fireDate = occ.fireDate

            // At-time first — it's the most important slot for this dose.
            await scheduleNotification(
                id: notificationID(medication: med, date: fireDate, suffix: "at"),
                title: "Time for \(med.name)",
                body: "\(String(format: "%.0f", med.doseAmount)) \(med.doseUnit)\(med.withFood ? " — take with food" : "")",
                fireDate: fireDate, medicationID: med.id, scheduledTimeHome: fireDate,
                isCritical: med.isCriticalAlert, categoryIdentifier: Self.categoryDose
            )
            used += 1

            // Pre-alert
            if med.preAlertMinutes > 0, used < budget {
                let preDate = fireDate.addingTimeInterval(-Double(med.preAlertMinutes) * 60)
                if preDate > now {
                    await scheduleNotification(
                        id: notificationID(medication: med, date: fireDate, suffix: "pre"),
                        title: med.name,
                        body: "Coming up in \(med.preAlertMinutes) min — get ready.",
                        fireDate: preDate, medicationID: med.id, scheduledTimeHome: fireDate,
                        isCritical: false, categoryIdentifier: nil
                    )
                    used += 1
                }
            }

            // Escalating follow-ups: +5, +15, +30
            for followUpMins in [5, 15, 30] {
                if used >= budget { break }
                await scheduleNotification(
                    id: notificationID(medication: med, date: fireDate, suffix: "followup\(followUpMins)"),
                    title: "Did you take \(med.name)?",
                    body: "Your dose was due \(followUpMins) min ago.",
                    fireDate: fireDate.addingTimeInterval(Double(followUpMins) * 60),
                    medicationID: med.id, scheduledTimeHome: fireDate,
                    isCritical: false, categoryIdentifier: Self.categoryDose
                )
                used += 1
            }
        }

        // Refill reminders: one next-morning nudge per medication that's low on stock.
        for med in medications where med.isActive && med.isLowOnSupply {
            guard used < budget, let fire = nextMorning(after: now, tz: homeTZ) else { break }
            let days = med.daysOfSupplyRemaining
            await scheduleNotification(
                id: notificationID(medication: med, date: fire, suffix: "refill"),
                title: "Refill \(med.name)",
                body: days.map { "About \($0) day\($0 == 1 ? "" : "s") left (\(med.inventoryCount) doses)." }
                    ?? "\(med.inventoryCount) doses left.",
                fireDate: fire, medicationID: med.id, scheduledTimeHome: fire,
                isCritical: false, categoryIdentifier: nil
            )
            used += 1
        }
    }

    /// Next occurrence of `hour`:00 in the given timezone (today if still ahead, else tomorrow).
    private func nextMorning(after now: Date, hour: Int = 9, tz: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        if let today = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now), today > now {
            return today
        }
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return nil }
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow)
    }

    // MARK: - Cancel

    /// Clear every pending dose notification (the app schedules nothing else),
    /// so `rescheduleAll` can rebuild the queue from scratch.
    func removeAllDoseNotifications() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
    }

    func removeAll(for medication: Medication) async {
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .filter { $0.content.userInfo["medicationID"] as? String == medication.id.uuidString }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    func removeNotification(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelFollowUps(for medication: Medication, scheduledAt fireDate: Date) async {
        let pending = await center.pendingNotificationRequests()
        let prefix = notificationIDPrefix(medication: medication, date: fireDate)
        let toRemove = pending
            .filter { $0.identifier.hasPrefix(prefix) && ($0.identifier.contains("followup") || $0.identifier.contains("snooze")) }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    // MARK: - Snooze

    /// Re-fires the dose reminder (with the same actions) `minutes` from now,
    /// keeping it tied to the original `scheduledTimeHome` so the reminder
    /// can still be matched back to its `DoseEvent`.
    func scheduleSnooze(for medication: Medication, scheduledTimeHome: Date, minutes: Int = 5) async {
        let fireDate = Date().addingTimeInterval(Double(minutes) * 60)
        await scheduleNotification(
            id: notificationID(medication: medication, date: scheduledTimeHome, suffix: "snooze\(Int(Date().timeIntervalSince1970))"),
            title: "Time for \(medication.name)",
            body: "Snoozed reminder — \(String(format: "%.0f", medication.doseAmount)) \(medication.doseUnit)\(medication.withFood ? " — take with food" : "")",
            fireDate: fireDate,
            medicationID: medication.id,
            scheduledTimeHome: scheduledTimeHome,
            isCritical: false,
            categoryIdentifier: Self.categoryDose
        )
    }

    // MARK: - Private helpers

    private func scheduleNotification(
        id: String,
        title: String,
        body: String,
        fireDate: Date,
        medicationID: UUID,
        scheduledTimeHome: Date,
        isCritical: Bool,
        categoryIdentifier: String?
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = [
            "medicationID": medicationID.uuidString,
            "scheduledTimeHome": scheduledTimeHome.timeIntervalSince1970
        ]
        if let cat = categoryIdentifier {
            content.categoryIdentifier = cat
        }

        // Always Time Sensitive; gate .critical behind feature flag per CLAUDE.md §hard-rules
        content.interruptionLevel = .timeSensitive
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Non-fatal: app functions without a scheduled notification
        }
    }

    private func notificationIDPrefix(medication: Medication, date: Date) -> String {
        "\(medication.id.uuidString)-\(Int(date.timeIntervalSince1970))"
    }

    private func notificationID(medication: Medication, date: Date, suffix: String) -> String {
        "\(notificationIDPrefix(medication: medication, date: date))-\(suffix)"
    }

    private func isoWeekday(from date: Date) -> Int {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
        // Calendar.weekday: 1=Sun, 2=Mon, …7=Sat
        // ISO: 1=Mon … 7=Sun
        return weekday == 1 ? 7 : weekday - 1
    }
}
