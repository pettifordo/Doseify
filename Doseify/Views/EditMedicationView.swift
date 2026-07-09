import SwiftUI
import SwiftData

struct EditMedicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let medication: Medication?
    private let isEditing: Bool

    // MARK: - Form state (initialised from medication in init, never from onAppear)
    @State private var name: String
    @State private var colorHex: String
    @State private var doseAmount: Double
    @State private var doseUnit: String
    @State private var withFood: Bool
    @State private var isActive: Bool
    @State private var isEveryDay: Bool           // explicit flag — avoids empty-set ambiguity
    @State private var daysOfWeek: Set<Int>     // actual selected days (1=Mon…7=Sun)
    @State private var timesOfDay: [TimeOfDay]
    @State private var onTimeWindow: Int
    @State private var cutoff: Int
    @State private var preAlert: Int
    @State private var shiftRate: Int
    @State private var inventory: Int
    @State private var refillThreshold: Int
    @State private var notes: String
    @State private var pharmacyName: String
    @State private var pharmacyPhone: String

    // Time picker — lifted to NavigationStack level to avoid sheet conflicts
    @State private var showTimePicker = false
    @State private var editingTimeIndex: Int? = nil
    @State private var pickerTime = Date()

    private let colorOptions: [(String, Color)] = [
        ("#7B9E87", Color.doseSage),
        ("#F2C4A4", Color.dosePeach),
        ("#718A94", Color.doseSlate),
        ("#E08080", Color(red: 0.88, green: 0.50, blue: 0.50)),
        ("#7B9DD8", Color(red: 0.48, green: 0.62, blue: 0.85)),
        ("#C9A96E", Color(red: 0.79, green: 0.66, blue: 0.43)),
    ]
    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // MARK: - Init — populate state immediately so re-opens always start fresh
    init(medication: Medication?) {
        self.medication = medication
        self.isEditing = medication != nil

        let med = medication
        _name            = State(initialValue: med?.name ?? "")
        _colorHex        = State(initialValue: med?.colorHex ?? "#7B9E87")
        _doseAmount      = State(initialValue: med?.doseAmount ?? 1.0)
        _doseUnit        = State(initialValue: med?.doseUnit ?? "capsule")
        _withFood        = State(initialValue: med?.withFood ?? false)
        _isActive        = State(initialValue: med?.isActive ?? true)
        let savedDays = med?.scheduledDaysOfWeek ?? []
        _isEveryDay      = State(initialValue: savedDays.isEmpty)
        _daysOfWeek      = State(initialValue: savedDays.isEmpty ? Set(1...7) : Set(savedDays))
        _timesOfDay      = State(initialValue: med?.scheduledTimesOfDay.isEmpty == false
                                    ? med!.scheduledTimesOfDay
                                    : [.morning])
        _onTimeWindow    = State(initialValue: med?.onTimeWindowMinutes ?? 5)
        _cutoff          = State(initialValue: med?.cutoffMinutes ?? 120)
        _preAlert        = State(initialValue: med?.preAlertMinutes ?? 10)
        _shiftRate       = State(initialValue: med?.timezoneShiftMinutesPerDay ?? 30)
        _inventory       = State(initialValue: med?.inventoryCount ?? 0)
        _refillThreshold = State(initialValue: med?.refillThresholdDays ?? 7)
        _notes           = State(initialValue: med?.notes ?? "")
        _pharmacyName    = State(initialValue: med?.pharmacyName ?? "")
        _pharmacyPhone   = State(initialValue: med?.pharmacyPhone ?? "")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                medicationSection
                scheduleSection
                notificationsSection
                Section("Travel") {
                    Stepper("Shift rate: \(shiftRate) min/day", value: $shiftRate, in: 15...60, step: 15)
                }
                inventorySection
                Section("Notes") {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isEditing ? "Edit Medication" : "Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showTimePicker, onDismiss: nil) {
                TimePickerSheet(time: $pickerTime) { applyPickedTime() }
            }
        }
    }

    // MARK: - Sections

    private var medicationSection: some View {
        Section("Medication") {
            TextField("Name", text: $name)
            colorPickerRow
            HStack {
                Text("Dose")
                Spacer()
                Stepper(value: $doseAmount, in: 0.5...20, step: 0.5) { EmptyView() }
                    .labelsHidden()
                Text(String(format: doseAmount == doseAmount.rounded() ? "%.0f" : "%.1f", doseAmount))
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
                TextField("unit", text: $doseUnit)
                    .multilineTextAlignment(.leading)
                    .frame(width: 80)
                    .foregroundStyle(.secondary)
            }
            Toggle("Take with food", isOn: $withFood)
            if isEditing { Toggle("Active", isOn: $isActive) }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            dayPickerView
            Divider().padding(.vertical, 4)
            timesView
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Stepper("Pre-alert: \(preAlert) min before", value: $preAlert, in: 0...60, step: 5)
            Stepper("On-time window: \(onTimeWindow) min", value: $onTimeWindow, in: 1...30)
            Stepper("Missed after: \(cutoff) min", value: $cutoff, in: 30...240, step: 30)
        }
    }

    private var inventorySection: some View {
        Section("Inventory") {
            Stepper("Current count: \(inventory)", value: $inventory, in: 0...999)
            Stepper("Refill reminder: \(refillThreshold) days left", value: $refillThreshold, in: 1...30)
            TextField("Pharmacy name (optional)", text: $pharmacyName)
            TextField("Pharmacy phone (optional)", text: $pharmacyPhone).keyboardType(.phonePad)
        }
    }

    // MARK: - Color picker

    private var colorPickerRow: some View {
        HStack {
            Text("Color")
            Spacer()
            HStack(spacing: 10) {
                ForEach(colorOptions, id: \.0) { hex, color in
                    Circle()
                        .fill(color)
                        .frame(width: 26, height: 26)
                        .overlay {
                            if hex == colorHex {
                                Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white)
                            }
                        }
                        .onTapGesture { colorHex = hex }
                }
            }
        }
    }

    // MARK: - Day picker
    // Always shows all 7 buttons.
    // "Every day" toggle: ON = all selected; OFF = none selected (user picks).
    // Tapping all 7 individually auto-enables "Every day" (collapses to empty).

    private var dayPickerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $isEveryDay) {
                Label("Every day", systemImage: "calendar")
            }
            .onChange(of: isEveryDay) { _, on in
                if on {
                    // Select all 7 visually
                    daysOfWeek = Set(1...7)
                }
                // When turning off, keep current daysOfWeek so user sees what was selected
            }

            // Day buttons — always visible
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { iso in
                    let selected = isEveryDay || daysOfWeek.contains(iso)
                    Button {
                        toggleDay(iso)
                    } label: {
                        Text(dayLabels[iso - 1])
                            .font(.caption.bold())
                            .frame(width: 38, height: 32)
                            .background(
                                selected ? Color.doseSage : Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !isEveryDay && daysOfWeek.isEmpty {
                Text("Select at least one day")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func toggleDay(_ iso: Int) {
        if isEveryDay {
            // Was "every day" — deselect this one day and switch to specific-days mode
            isEveryDay = false
            daysOfWeek = Set(1...7)
            daysOfWeek.remove(iso)
        } else if daysOfWeek.contains(iso) {
            daysOfWeek.remove(iso)
            // If everything was deselected stay in specific mode (show warning)
        } else {
            daysOfWeek.insert(iso)
            if daysOfWeek.count == 7 {
                // All 7 manually selected — flip to "every day"
                isEveryDay = true
            }
        }
    }

    // MARK: - Times section

    private var timesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(timesOfDay.enumerated()), id: \.offset) { index, tod in
                HStack {
                    Image(systemName: "clock").foregroundStyle(Color.doseSage).frame(width: 24)
                    Button(tod.displayString) { openPicker(editing: index) }
                        .foregroundStyle(.primary)
                    Spacer()
                    if timesOfDay.count > 1 {
                        Button {
                            timesOfDay.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                if index < timesOfDay.count - 1 {
                    Divider().padding(.leading, 36)
                }
            }
            Button {
                openPicker(editing: nil)
            } label: {
                Label("Add dose time", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.doseSage)
                    .padding(.top, timesOfDay.isEmpty ? 0 : 8)
            }
        }
    }

    // MARK: - Time picker helpers

    private func openPicker(editing index: Int?) {
        editingTimeIndex = index
        if let idx = index {
            let tod = timesOfDay[idx]
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = tod.hour; comps.minute = tod.minute
            pickerTime = Calendar.current.date(from: comps) ?? Date()
        } else {
            let last = timesOfDay.sorted().last ?? .morning
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = (last.hour + 12) % 24; comps.minute = last.minute
            pickerTime = Calendar.current.date(from: comps) ?? Date()
        }
        showTimePicker = true
    }

    private func applyPickedTime() {
        let cal = Calendar.current
        let tod = TimeOfDay(hour: cal.component(.hour, from: pickerTime),
                            minute: cal.component(.minute, from: pickerTime))
        if let idx = editingTimeIndex, timesOfDay.indices.contains(idx) {
            timesOfDay[idx] = tod
        } else {
            timesOfDay.append(tod)
        }
        timesOfDay = Array(Set(timesOfDay)).sorted()
        editingTimeIndex = nil
    }

    // MARK: - Save

    private func save() {
        // empty array = daily in the data model
        let scheduledDays = isEveryDay ? [] : Array(daysOfWeek).sorted()
        let store = MedicationStore(modelContext: modelContext)

        if let med = medication {
            med.name = name; med.colorHex = colorHex
            med.doseAmount = doseAmount; med.doseUnit = doseUnit
            med.withFood = withFood; med.isActive = isActive
            med.scheduledTimesOfDay = timesOfDay
            med.scheduledDaysOfWeek = scheduledDays
            med.onTimeWindowMinutes = onTimeWindow
            med.cutoffMinutes = cutoff; med.preAlertMinutes = preAlert
            med.timezoneShiftMinutesPerDay = shiftRate
            med.inventoryCount = inventory; med.refillThresholdDays = refillThreshold
            med.notes = notes.isEmpty ? nil : notes
            med.pharmacyName = pharmacyName.isEmpty ? nil : pharmacyName
            med.pharmacyPhone = pharmacyPhone.isEmpty ? nil : pharmacyPhone
            try? store.save()
        } else {
            let med = Medication(
                name: name, colorHex: colorHex,
                doseAmount: doseAmount, doseUnit: doseUnit,
                scheduledDaysOfWeek: scheduledDays,
                scheduledTimesOfDay: timesOfDay,
                withFood: withFood,
                onTimeWindowMinutes: onTimeWindow,
                cutoffMinutes: cutoff, preAlertMinutes: preAlert,
                timezoneShiftMinutesPerDay: shiftRate,
                inventoryCount: inventory, refillThresholdDays: refillThreshold
            )
            med.notes = notes.isEmpty ? nil : notes
            med.pharmacyName = pharmacyName.isEmpty ? nil : pharmacyName
            med.pharmacyPhone = pharmacyPhone.isEmpty ? nil : pharmacyPhone
            try? store.addMedication(med)
        }

        Task {
            let store = MedicationStore(modelContext: modelContext)
            guard let settings = try? store.settings() else { return }
            // New/edited schedules need their upcoming DoseEvents generated,
            // otherwise Today shows "Nothing scheduled" until the next launch.
            try? store.generateUpcomingDoses(settings: settings)
            if let inputs = try? store.notificationInputs() {
                await NotificationService.shared.rescheduleAll(
                    doses: inputs.doses, medications: inputs.medications,
                    settings: inputs.settings, nightAlarmActive: inputs.nightAlarm
                )
            }
            PhoneConnectivityService.shared.syncTodayToWatch()
        }
        dismiss()
    }
}

// MARK: - TimeOfDay: Identifiable (for ForEach dedup)

extension TimeOfDay: Identifiable {
    public var id: Int { totalMinutes }
}

// MARK: - TimePickerSheet

struct TimePickerSheet: View {
    @Binding var time: Date
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
                .navigationTitle("Pick time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onConfirm(); dismiss() }
                    }
                }
        }
    }
}
