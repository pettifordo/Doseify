import SwiftUI
import SwiftData

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.name) private var medications: [Medication]
    @State private var showAdd = false
    @State private var showExamples = false
    @State private var editTarget: Medication?

    var body: some View {
        NavigationStack {
            Group {
                if medications.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(medications) { med in
                            MedicationRowView(medication: med)
                                .contentShape(Rectangle())
                                .onTapGesture { editTarget = med }
                        }
                        .onDelete(perform: deleteMedications)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showAdd = true
                        } label: {
                            Label("Add Medication", systemImage: "plus")
                        }
                        Button {
                            showExamples = true
                        } label: {
                            Label("Add from Examples…", systemImage: "list.bullet.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            EditMedicationView(medication: nil)
        }
        .sheet(isPresented: $showExamples) {
            ExampleMedicationsView()
        }
        .sheet(item: $editTarget) { med in
            EditMedicationView(medication: med)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "No medications yet",
                systemImage: "pills",
                description: Text("Add your medications to start tracking doses.")
            )
            VStack(spacing: 12) {
                Button {
                    showAdd = true
                } label: {
                    Text("Add Medication")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showExamples = true
                } label: {
                    Text("Add from Examples (Acalabrutinib, etc.)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)
        }
    }

    private func deleteMedications(at offsets: IndexSet) {
        let store = MedicationStore(modelContext: modelContext)
        for i in offsets {
            try? store.deleteMedication(medications[i])
        }
    }
}

// MARK: - Row

struct MedicationRowView: View {
    let medication: Medication

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.fromHex(medication.colorHex))
                .frame(width: 36, height: 36)
                .overlay { Image(systemName: "pill.fill").foregroundStyle(.white).font(.footnote) }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(medication.name).font(.body.weight(.semibold))
                    if !medication.isActive {
                        Text("Paused")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(scheduleLabel).font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer()

            if medication.needsRefill {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .help("Refill soon — \(medication.inventoryCount) remaining")
            }
        }
        .padding(.vertical, 4)
    }

    private var scheduleLabel: String {
        let times = medication.scheduledTimesOfDay.sorted().map(\.displayString).joined(separator: ", ")
        let days = medication.scheduledDaysOfWeek.isEmpty ? "Daily" : dayAbbrevs(medication.scheduledDaysOfWeek)
        return "\(String(format: "%.0f", medication.doseAmount)) \(medication.doseUnit) · \(days) at \(times)"
    }

    private func dayAbbrevs(_ iso: [Int]) -> String {
        let names = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return iso.sorted().compactMap { $0 < names.count ? names[$0] : nil }.joined(separator: "/")
    }
}
