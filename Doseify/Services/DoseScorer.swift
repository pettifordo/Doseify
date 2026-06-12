import Foundation

/// Pure scoring logic — no side effects, no dependencies.
struct DoseScorer {

    /// Compute a score 0–100 for a logged dose.
    ///
    /// - Parameters:
    ///   - scheduledTime: when the dose was due
    ///   - loggedTime: when the user tapped "taken"
    ///   - onTimeWindowMinutes: seconds inside which score = 100 (default 5)
    ///   - cutoffMinutes: minutes after which status is missed (default 120)
    /// - Returns: score 0–100; negative loggedTime delta (early) is treated as 0-offset.
    static func score(
        scheduledTime: Date,
        loggedTime: Date,
        onTimeWindowMinutes: Int = 5,
        cutoffMinutes: Int = 120
    ) -> Double {
        let deltaSeconds = loggedTime.timeIntervalSince(scheduledTime)
        let deltaMins = deltaSeconds / 60.0

        // Taken early or within on-time window → 100
        if deltaMins <= Double(onTimeWindowMinutes) {
            return 100.0
        }

        // Past cutoff → 0 (caller should mark missed)
        let cutoff = Double(cutoffMinutes)
        if deltaMins >= cutoff {
            return 0.0
        }

        // Linear decline from 100 at onTimeWindow to 0 at cutoff
        let window = Double(onTimeWindowMinutes)
        let ratio = (deltaMins - window) / (cutoff - window)
        return max(0, 100.0 * (1.0 - ratio))
    }

    /// Determine the DoseStatus for a dose that has not been logged.
    ///
    /// - Parameters:
    ///   - effectiveScheduledTime: the shifted scheduled time
    ///   - now: current time (injectable for testing)
    ///   - cutoffMinutes: minutes after which the dose is missed
    static func pendingStatus(
        effectiveScheduledTime: Date,
        now: Date = Date(),
        cutoffMinutes: Int = 120
    ) -> DoseStatus {
        let elapsed = now.timeIntervalSince(effectiveScheduledTime) / 60.0
        if elapsed >= Double(cutoffMinutes) {
            return .missed
        }
        return .pending
    }
}
