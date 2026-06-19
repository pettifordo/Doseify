import SwiftUI
import SwiftData

/// Lets the user pick from a small library of common CLL-related medication
/// templates and add them as a starting point. Schedules and dosing can be
/// edited afterwards like any other medication.
struct ExampleMedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Medication.name) private var existingMedications: [Medication]

    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List(ExampleMedicationLibrary.all) { template in
                Button {
                    toggle(template)
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.fromHex(template.colorHex))
                            .frame(width: 32, height: 32)
                            .overlay { Image(systemName: "pill.fill").foregroundStyle(.white).font(.caption) }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.body.weight(.semibold))
                            Text(template.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if alreadyAdded(template) {
                            Text("Added")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if selected.contains(template.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(alreadyAdded(template))
            }
            .navigationTitle("Example Medications")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addSelected() }
                        .disabled(selected.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("These are starting points — you can edit the dose, schedule, and timing windows for each before relying on its reminders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }

    private func alreadyAdded(_ template: ExampleMedicationLibrary.Template) -> Bool {
        existingMedications.contains { $0.name.caseInsensitiveCompare(template.name) == .orderedSame }
    }

    private func toggle(_ template: ExampleMedicationLibrary.Template) {
        if selected.contains(template.id) {
            selected.remove(template.id)
        } else {
            selected.insert(template.id)
        }
    }

    private func addSelected() {
        let store = MedicationStore(modelContext: modelContext)
        let toAdd = ExampleMedicationLibrary.all.filter { selected.contains($0.id) }
        for template in toAdd {
            try? store.addMedication(template.makeMedication())
        }

        Task {
            guard let settings = try? store.settings() else { return }
            // Generate today/upcoming DoseEvents for the newly added medications,
            // otherwise Today shows "Nothing scheduled" until the next launch.
            try? store.generateUpcomingDoses(settings: settings)
            if let inputs = try? store.notificationInputs() {
                await NotificationService.shared.rescheduleAll(
                    doses: inputs.doses, medications: inputs.medications,
                    settings: inputs.settings, nightAlarmActive: inputs.nightAlarm
                )
            }
        }

        dismiss()
    }
}
