import SwiftUI

/// Static, in-app privacy statement. No network access — this is the
/// entire policy, shipped with the app and shown from Settings.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Privacy")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 4)

                section(
                    title: "Your data stays on this device",
                    body: "Doseify stores everything — your medications, dose history, trips, and settings — locally on this iPhone (and your Apple Watch, via direct device-to-device sync). There is no account, no server, and no iCloud sync. Nothing is uploaded anywhere."
                )

                section(
                    title: "No analytics or tracking",
                    body: "Doseify contains no analytics, telemetry, crash reporting, or third-party SDKs of any kind. Your usage of this app is never measured, recorded, or shared."
                )

                section(
                    title: "Notifications",
                    body: "Dose reminders are scheduled locally on your device using Apple's notification system. No reminder content ever leaves your phone."
                )

                section(
                    title: "Apple Health",
                    body: "If you choose to use it, Doseify can import your medication list from the Health app so you don't have to re-enter it. This is read-only and limited to your medications — Doseify does not read any other Health data and does not write anything to Health. You can revoke this permission at any time in iOS Settings → Privacy & Security → Health."
                )

                section(
                    title: "Location",
                    body: "Doseify does not use your location. Timezone changes are detected using your device's system timezone setting only."
                )

                section(
                    title: "Deleting your data",
                    body: "Deleting the app removes all of its data immediately and permanently. Because there is no cloud backup, this cannot be undone — Doseify does not retain a copy anywhere."
                )

                section(
                    title: "Medical disclaimer",
                    body: "Doseify is a personal organisational tool, not a medical device. Dose timing suggestions — including any timezone or travel adjustments — are indicative only. Always confirm your medication schedule, and any changes to it, with your doctor or pharmacist."
                )

                section(
                    title: "Contact",
                    body: "This app is developed for personal use. If you have questions about this privacy statement, contact the developer directly."
                )

                Text("Last updated: \(Self.lastUpdated)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private static let lastUpdated: String = "July 2026"
}

#Preview {
    NavigationStack { PrivacyPolicyView() }
}
