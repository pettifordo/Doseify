import Foundation
import WatchConnectivity

/// Watch side of the bridge. Holds the day's pending doses (pushed from the
/// phone) and sends a "log" message back when the user taps Take.
@MainActor
final class WatchConnectivityService: NSObject, ObservableObject {

    static let shared = WatchConnectivityService()

    @Published var doses: [WatchDose] = []
    @Published var isActivated = false

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Optimistically drop the dose, then tell the phone to log it. Uses an
    /// immediate message when reachable, else a guaranteed background transfer.
    func logDose(_ dose: WatchDose) {
        doses.removeAll { $0.id == dose.id }
        let message = WatchSync.logMessage(doseID: dose.id, time: Date())
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
        }
    }

    private func apply(_ context: [String: Any]) {
        if let decoded = WatchSync.decodeDoses(context) {
            doses = decoded
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.isActivated = activationState == .activated
            self.apply(context)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
}
