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
            await NotificationService.shared.cancel(doseID: dose.id)
            // Keep the Watch's dose list in step — the action may have been
            // tapped on a mirrored Watch notification or the phone lock screen.
            PhoneConnectivityService.shared.syncTodayToWatch()

        case NotificationService.actionSkip:
            try? store.skipDose(dose)
            await NotificationService.shared.cancel(doseID: dose.id)
            PhoneConnectivityService.shared.syncTodayToWatch()

        case NotificationService.actionSnooze:
            await NotificationService.shared.scheduleSnooze(
                for: medication, doseID: dose.id, scheduledTimeHome: scheduledTimeHome
            )

        default:
            break
        }
    }
}
