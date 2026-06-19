import Foundation
import UserNotifications

/// Manages the UNUserNotificationCenter queue.
///
/// Reminders are scheduled from the **pending `DoseEvent` records** (which already
/// carry the trip-shifted `effectiveScheduledTime`), keyed by `dose.id`. That makes
/// the queue trip-aware and lets us wipe a dose's reminders the instant it's logged
/// — so a recorded dose never keeps nagging. iOS caps pending notifications at 64,
/// so we fill a shared, soonest-first budget.
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

    // MARK: - Schedule notifications from pending doses

    /// Rebuild the pending-notification queue from the current **pending** dose
    /// records. Logged/skipped/missed doses get nothing, so recorded doses stop
    /// reminding. Times come from `effectiveScheduledTime`, so travel shifts apply.
    ///
    /// - Parameter nightAlarmActive: the active trip wants a repeating wake-up
    ///   alarm for any dose that lands inside the user's sleep window.
    func rescheduleAll(
        doses: [DoseEvent],
        medications: [Medication],
        settings: UserSettings,
        nightAlarmActive: Bool,
        upcomingDays: Int = 7
    ) async {
        await removeAllDoseNotifications()

        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: upcomingDays, to: now) ?? now

        // Pending + still-future doses only, soonest first so the nearest reminders
        // for every medication are scheduled before the shared budget runs out.
        let pending = doses
            .filter { $0.status == .pending && $0.effectiveScheduledTime > now && $0.effectiveScheduledTime <= horizon }
            .sorted { $0.effectiveScheduledTime < $1.effectiveScheduledTime }

        let budget = 60
        var used = 0

        for dose in pending {
            if used >= budget { break }
            guard let med = dose.medication else { continue }
            let fireDate = dose.effectiveScheduledTime

            // A dose that lands in the sleep window during travel gets a repeating
            // wake-up alarm instead of the usual single reminder + soft follow-ups.
            if nightAlarmActive,
               Self.isInSleepWindow(fireDate, timezoneID: dose.effectiveTimezone, settings: settings) {
                for i in 0..<6 {
                    if used >= budget { break }
                    await scheduleNotification(
                        id: doseID(dose, "alarm\(i)"),
                        title: "⏰ Time for \(med.name)",
                        body: "Night dose — \(doseBody(med))",
                        fireDate: fireDate.addingTimeInterval(Double(i) * 60),
                        doseID: dose.id, medicationID: med.id, scheduledTimeHome: dose.scheduledTimeHome,
                        isCritical: med.isCriticalAlert, categoryIdentifier: Self.categoryDose
                    )
                    used += 1
                }
                continue
            }

            // At-time — the most important slot for this dose.
            await scheduleNotification(
                id: doseID(dose, "at"),
                title: "Time for \(med.name)", body: doseBody(med),
                fireDate: fireDate, doseID: dose.id, medicationID: med.id,
                scheduledTimeHome: dose.scheduledTimeHome,
                isCritical: med.isCriticalAlert, categoryIdentifier: Self.categoryDose
            )
            used += 1

            // Pre-alert.
            if med.preAlertMinutes > 0, used < budget {
                let preDate = fireDate.addingTimeInterval(-Double(med.preAlertMinutes) * 60)
                if preDate > now {
                    await scheduleNotification(
                        id: doseID(dose, "pre"),
                        title: med.name, body: "Coming up in \(med.preAlertMinutes) min — get ready.",
                        fireDate: preDate, doseID: dose.id, medicationID: med.id,
                        scheduledTimeHome: dose.scheduledTimeHome,
                        isCritical: false, categoryIdentifier: nil
                    )
                    used += 1
                }
            }

            // Escalating follow-ups: +5, +15, +30.
            for followUpMins in [5, 15, 30] {
                if used >= budget { break }
                await scheduleNotification(
                    id: doseID(dose, "followup\(followUpMins)"),
                    title: "Did you take \(med.name)?",
                    body: "Your dose was due \(followUpMins) min ago.",
                    fireDate: fireDate.addingTimeInterval(Double(followUpMins) * 60),
                    doseID: dose.id, medicationID: med.id, scheduledTimeHome: dose.scheduledTimeHome,
                    isCritical: false, categoryIdentifier: Self.categoryDose
                )
                used += 1
            }
        }

        // Refill reminders: one next-morning nudge per medication that's low on stock.
        let homeTZ = TimeZone(identifier: settings.homeTimezone) ?? .current
        for med in medications where med.isActive && med.isLowOnSupply {
            guard used < budget, let fire = nextMorning(after: now, tz: homeTZ) else { break }
            let days = med.daysOfSupplyRemaining
            await scheduleNotification(
                id: "refill-\(med.id.uuidString)",
                title: "Refill \(med.name)",
                body: days.map { "About \($0) day\($0 == 1 ? "" : "s") left (\(med.inventoryCount) doses)." }
                    ?? "\(med.inventoryCount) doses left.",
                fireDate: fire, doseID: nil, medicationID: med.id, scheduledTimeHome: fire,
                isCritical: false, categoryIdentifier: nil
            )
            used += 1
        }
    }

    // MARK: - Cancel

    /// Clear every pending dose notification so `rescheduleAll` can rebuild cleanly.
    func removeAllDoseNotifications() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
    }

    /// Remove every pending notification (at-time, pre-alert, follow-ups, night
    /// alarm, snooze) for one dose — called the moment it's logged or skipped.
    func cancel(doseID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let prefix = doseID.uuidString
        center.removePendingNotificationRequests(
            withIdentifiers: pending.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier)
        )
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

    // MARK: - Snooze

    /// Re-fires the dose reminder `minutes` from now, keyed to the same dose so it
    /// is cleared if the dose is later logged.
    func scheduleSnooze(for medication: Medication, doseID id: UUID, scheduledTimeHome: Date, minutes: Int = 5) async {
        let fireDate = Date().addingTimeInterval(Double(minutes) * 60)
        await scheduleNotification(
            id: "\(id.uuidString)-snooze\(Int(Date().timeIntervalSince1970))",
            title: "Time for \(medication.name)",
            body: "Snoozed reminder — \(doseBody(medication))",
            fireDate: fireDate,
            doseID: id, medicationID: medication.id, scheduledTimeHome: scheduledTimeHome,
            isCritical: false, categoryIdentifier: Self.categoryDose
        )
    }

    // MARK: - Sleep window

    /// Whether `date`, read in `timezoneID`, falls inside the user's sleep window.
    nonisolated static func isInSleepWindow(_ date: Date, timezoneID: String, settings: UserSettings) -> Bool {
        let tz = TimeZone(identifier: timezoneID) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let mins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = settings.sleepWindowStart.hour * 60 + settings.sleepWindowStart.minute
        let end = settings.sleepWindowEnd.hour * 60 + settings.sleepWindowEnd.minute
        if start == end { return false }
        if start < end { return mins >= start && mins < end }
        return mins >= start || mins < end   // window wraps past midnight
    }

    // MARK: - Private helpers

    private func doseID(_ dose: DoseEvent, _ suffix: String) -> String {
        "\(dose.id.uuidString)-\(suffix)"
    }

    private func doseBody(_ med: Medication) -> String {
        "\(String(format: "%.0f", med.doseAmount)) \(med.doseUnit)\(med.withFood ? " — take with food" : "")"
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

    private func scheduleNotification(
        id: String,
        title: String,
        body: String,
        fireDate: Date,
        doseID: UUID?,
        medicationID: UUID,
        scheduledTimeHome: Date,
        isCritical: Bool,
        categoryIdentifier: String?
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        var info: [String: Any] = [
            "medicationID": medicationID.uuidString,
            "scheduledTimeHome": scheduledTimeHome.timeIntervalSince1970
        ]
        if let doseID { info["doseID"] = doseID.uuidString }
        content.userInfo = info
        if let cat = categoryIdentifier {
            content.categoryIdentifier = cat
        }

        // Always Time Sensitive; gate .critical behind the entitlement flag per
        // CLAUDE.md hard rule 7 (off until/unless Apple approves Critical Alerts).
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
}
