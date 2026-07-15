import SwiftUI
import SwiftData

/// Import medications from Apple Health (iOS 26+, read-only).
///
/// Health exposes the user's medication *list* but not its schedule times, so
/// imported drugs default to a single morning dose the user can adjust afterwards.
struct HealthImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case loading
        case unsupported
        case empty
        case list
        case done(Int)
    }

    @State private var phase: Phase = .loading
    @State private var found: [HealthKitGateway.ImportedMedication] = []
    @State private var selected: Set<UUID> = []

    private let gateway = HealthKitGateway.shared

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Apple Health")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if phase == .list {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Import") { importSelected() }
                                .disabled(selected.isEmpty)
                                .fontWeight(.semibold)
                        }
                    }
                }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Reading Apple Health…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unsupported:
            ContentUnavailableView {
                Label("Not available", systemImage: "heart.text.square")
            } description: {
                Text("Importing medications needs iOS 26 or later, where Apple Health makes your medication list available to apps. Writing doses back to Health isn't offered by Apple, so TimeShift Meds stays your record of what you've taken.")
            }

        case .empty:
            ContentUnavailableView {
                Label("No medications found", systemImage: "pills")
            } description: {
                Text("Either Apple Health has no medications, or access wasn't granted. You can manage access in Settings ▸ Health ▸ Data Access & Devices ▸ TimeShift Meds.")
            }

        case .list:
            List {
                Section {
                    ForEach(found) { med in
                        Button {
                            toggle(med.id)
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(med.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(med.id) ? Color.doseSage : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(med.name).foregroundStyle(.primary)
                                    if med.hasSchedule {
                                        Text("Scheduled in Health")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Found in Apple Health")
                } footer: {
                    Text("Imported medications start with one morning dose — set the real times, dose, and travel rules afterwards.")
                }
            }

        case .done(let count):
            ContentUnavailableView {
                Label("Imported", systemImage: "checkmark.circle.fill")
            } description: {
                Text("Added \(count) medication\(count == 1 ? "" : "s") to TimeShift Meds. Open each one to set its schedule and dose.")
            } actions: {
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        guard gateway.isMedicationImportSupported else { phase = .unsupported; return }
        _ = await gateway.requestMedicationReadAuthorization()
        let meds = await gateway.fetchHealthMedications()
        found = meds
        selected = Set(meds.map { $0.id })
        phase = meds.isEmpty ? .empty : .list
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func importSelected() {
        let store = MedicationStore(modelContext: modelContext)
        let toImport = found.filter { selected.contains($0.id) }
        var count = 0
        for item in toImport {
            let med = Medication(name: item.name, scheduledTimesOfDay: [.morning])
            if (try? store.addMedication(med)) != nil { count += 1 }
        }
        phase = .done(count)
    }
}
