import Foundation
import SwiftData
import WatchConnectivity

/// Phone side of the Watch bridge. Pushes the day's pending doses to the Watch
/// (latest-state via `updateApplicationContext`) and applies "log" messages the
/// Watch sends back — logging the dose, cancelling its reminders, and re-syncing.
@MainActor
final class PhoneConnectivityService: NSObject, ObservableObject {

    static let shared = PhoneConnectivityService()
    private var modelContext: ModelContext?

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send the current day's still-pending doses to the Watch.
    func syncTodayToWatch() {
        guard WCSession.isSupported(), let modelContext else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let doses = Self.todayWatchDoses(modelContext: modelContext)
        try? session.updateApplicationContext(WatchSync.encodeDoses(doses))
    }

    static func todayWatchDoses(modelContext: ModelContext) -> [WatchDose] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let all = (try? modelContext.fetch(FetchDescriptor<DoseEvent>())) ?? []
        return all
            .filter { $0.status == .pending && $0.effectiveScheduledTime >= start && $0.effectiveScheduledTime < end }
            .sorted { $0.effectiveScheduledTime < $1.effectiveScheduledTime }
            .map {
                WatchDose(
                    id: $0.id,
                    medName: $0.medication?.name ?? "Dose",
                    scheduledTime: $0.effectiveScheduledTime,
                    colorHex: $0.medication?.colorHex ?? "#7B9E87"
                )
            }
    }

    /// Apply a dose log that arrived from the Watch.
    private func applyLog(doseID: UUID, time: Date) {
        guard let modelContext else { return }
        let store = MedicationStore(modelContext: modelContext)
        let all = (try? modelContext.fetch(FetchDescriptor<DoseEvent>())) ?? []
        guard let dose = all.first(where: { $0.id == doseID }), dose.status == .pending else {
            syncTodayToWatch()   // already logged elsewhere — just refresh the Watch
            return
        }
        try? store.logDose(dose, at: time)
        let id = dose.id
        Task { await NotificationService.shared.cancel(doseID: id) }
        if let inputs = try? store.notificationInputs() {
            Task {
                await NotificationService.shared.rescheduleAll(
                    doses: inputs.doses, medications: inputs.medications,
                    settings: inputs.settings, nightAlarmActive: inputs.nightAlarm
                )
            }
        }
        syncTodayToWatch()
    }

    private func handle(_ payload: [String: Any]) {
        guard let log = WatchSync.parseLog(payload) else { return }
        applyLog(doseID: log.id, time: log.time)
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityService: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.syncTodayToWatch() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.handle(userInfo) }
    }

    // iOS requires these so the session can re-pair when the user switches watches.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
