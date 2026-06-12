import Foundation
import SwiftData

/// Translates a tapped notification action (Taken now / Snooze / Skip) into
/// the corresponding SwiftData update, mirroring the manual logging path in
/// TodayView's DoseActionSheet.
@MainActor
enum DoseNotificationActionHandler {
    static func handle(
        actionIdentifier: String,
        medicationID: UUID?,
        scheduledTimeHome: Date?,
        modelContext: ModelContext
    ) async {
        guard let medicationID, let scheduledTimeHome else { return }

        let store = MedicationStore(modelContext: modelContext)
        guard let dose = try? store.findDose(medicationID: medicationID, scheduledTimeHome: scheduledTimeHome),
              let medication = dose.medication else { return }

        switch actionIdentifier {
        case NotificationService.actionTaken:
            try? store.logDose(dose, at: Date())
            await NotificationService.shared.cancelFollowUps(for: medication, scheduledAt: dose.effectiveScheduledTime)

        case NotificationService.actionSkip:
            try? store.skipDose(dose)
            await NotificationService.shared.cancelFollowUps(for: medication, scheduledAt: dose.effectiveScheduledTime)

        case NotificationService.actionSnooze:
            await NotificationService.shared.scheduleSnooze(for: medication, scheduledTimeHome: scheduledTimeHome)

        default:
            break
        }
    }
}
