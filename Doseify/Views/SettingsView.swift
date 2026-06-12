import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: UserSettings?
    @State private var showHealthImport = false

    var body: some View {
        NavigationStack {
            Group {
                if let settings {
                    Form {
                        Section("Timezone") {
                            HStack {
                                Text("Home timezone")
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { settings.homeTimezone },
                                    set: { settings.homeTimezone = $0; save() }
                                )) {
                                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { id in
                                        Text(id).tag(id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                            Toggle("Auto-detect on travel", isOn: Binding(
                                get: { settings.autoDetectTimezone },
                                set: { settings.autoDetectTimezone = $0; save() }
                            ))
                        }

                        Section("Appearance") {
                            Picker("Theme", selection: Binding(
                                get: { settings.theme },
                                set: { settings.theme = $0; save() }
                            )) {
                                ForEach(AppTheme.allCases, id: \.self) { t in
                                    Text(t.rawValue.capitalized).tag(t)
                                }
                            }
                        }

                        Section {
                            Button {
                                showHealthImport = true
                            } label: {
                                Label("Import from Apple Health", systemImage: "heart.text.square")
                            }
                        } header: {
                            Text("Apple Health")
                        } footer: {
                            Text("Bring in medications you already track in Health. (Doseify can't write doses back — Apple doesn't offer that — so Doseify stays your record of what you've taken.)")
                        }

                        Section("About") {
                            LabeledContent("Version", value: appVersion)
                            LabeledContent("For", value: "CLL medication management")
                            NavigationLink("Privacy") {
                                PrivacyPolicyView()
                            }
                            Text("No data leaves your device. No analytics, no tracking.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Settings")
        }
        .onAppear { loadSettings() }
        .sheet(isPresented: $showHealthImport) {
            HealthImportView()
        }
    }

    private func loadSettings() {
        let store = MedicationStore(modelContext: modelContext)
        settings = try? store.settings()
    }

    private func save() {
        try? modelContext.save()
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}
