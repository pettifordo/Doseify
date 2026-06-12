import SwiftUI
import SwiftData
import UserNotifications

@main
struct DoseifyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    static let container: ModelContainer = {
        let schema = Schema([
            Medication.self,
            DoseEvent.self,
            Trip.self,
            Flight.self,
            Layover.self,
            DoseOverride.self,
            SideEffectLog.self,
            UserSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    requestPermissions()
                    seedDebugDataIfNeeded()
                }
        }
        .modelContainer(Self.container)
    }

    private func requestPermissions() {
        Task {
            _ = await NotificationService.shared.requestAuthorization()
            // HealthKit is only used for the opt-in "Import from Apple Health" flow,
            // which requests read access at the moment the user taps it — no prompt here.
        }
    }

    /// Populates demo data for screenshots/UI dev. No-ops in Release builds
    /// and no-ops if the store already has medications.
    private func seedDebugDataIfNeeded() {
        #if DEBUG
        DebugSeeder.seedIfNeeded(modelContext: Self.container.mainContext)
        #endif
    }
}

// MARK: - AppDelegate for notification actions

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Handle notification action buttons (Taken now / Snooze / Skip)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let medicationID = (userInfo["medicationID"] as? String).flatMap(UUID.init)
        let scheduledTimeHome = (userInfo["scheduledTimeHome"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let actionIdentifier = response.actionIdentifier

        Task { @MainActor in
            await DoseNotificationActionHandler.handle(
                actionIdentifier: actionIdentifier,
                medicationID: medicationID,
                scheduledTimeHome: scheduledTimeHome,
                modelContext: DoseifyApp.container.mainContext
            )
            completionHandler()
        }
    }

    // Show notifications while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
