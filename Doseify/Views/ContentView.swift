import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(0)

            MedicationsView()
                .tabItem { Label("Medications", systemImage: "pills") }
                .tag(1)

            AdherenceView()
                .tabItem { Label("Adherence", systemImage: "chart.bar") }
                .tag(2)

            TripsView()
                .tabItem { Label("Travel", systemImage: "airplane") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(4)
        }
        .tint(Color.doseSage)
        .onAppear { generateDosesIfNeeded() }
    }

    private func generateDosesIfNeeded() {
        let store = MedicationStore(modelContext: modelContext)
        guard let settings = try? store.settings() else { return }
        try? store.generateUpcomingDoses(settings: settings)
        try? store.rolloverMissedDoses(settings: settings)
        // Rebuild the notification queue on launch from the current pending doses so
        // it rolls forward, reflects trip shifts, and drops anything already logged.
        if let inputs = try? store.notificationInputs() {
            Task {
                await NotificationService.shared.rescheduleAll(
                    doses: inputs.doses, medications: inputs.medications,
                    settings: inputs.settings, nightAlarmActive: inputs.nightAlarm
                )
            }
        }
        PhoneConnectivityService.shared.syncTodayToWatch()
    }
}
