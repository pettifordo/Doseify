import Foundation
import SwiftData

@Model
final class DoseEvent {
    var id: UUID
    var medication: Medication?

    /// The canonical scheduled time anchored in the user's home timezone (stored as UTC Date).
    var scheduledTimeHome: Date

    /// After timezone shift adjustment — what actually fires the notification.
    var effectiveScheduledTime: Date

    /// IANA identifier of the timezone in effect when this event was scheduled.
    var effectiveTimezone: String

    var loggedTime: Date?
    var status: DoseStatus
    var score: Double   // 0–100
    var note: String?

    /// Non-nil when user has edited a logged dose; preserves original.
    var originalLoggedTime: Date?

    /// FK to a `DoseOverride` when the user manually set this dose's time in the
    /// trip preview (SPEC §2.4.3 step 7). Nil = engine-computed time.
    var overrideAppliedId: UUID?

    init(
        medication: Medication,
        scheduledTimeHome: Date,
        effectiveScheduledTime: Date,
        effectiveTimezone: String
    ) {
        self.id = UUID()
        self.medication = medication
        self.scheduledTimeHome = scheduledTimeHome
        self.effectiveScheduledTime = effectiveScheduledTime
        self.effectiveTimezone = effectiveTimezone
        self.status = .pending
        self.score = 0
    }

    var isPast: Bool {
        effectiveScheduledTime < Date()
    }

    var isLoggable: Bool {
        status == .pending
    }
}
