import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DoseEvent.effectiveScheduledTime, order: .reverse) private var allDoses: [DoseEvent]
    @Query private var medications: [Medication]

    @State private var selectedDose: DoseEvent?
    @State private var showAllHistory = false
    @State private var showMilestone: Int?

    // Today's still-pending doses, chronological. Once a dose is recorded
    // (taken/missed/skipped) it moves to the "Last 24 hours" section instead.
    private var todayDoses: [DoseEvent] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        return allDoses
            .filter { $0.status == .pending && $0.effectiveScheduledTime >= today && $0.effectiveScheduledTime < tomorrow }
            .sorted { $0.effectiveScheduledTime < $1.effectiveScheduledTime }
    }

    // Today's pending doses grouped by their scheduled time, so meds due at the
    // same moment can be logged together ("take all due at 8:00").
    private var todayGroups: [(time: Date, doses: [DoseEvent])] {
        Dictionary(grouping: todayDoses) { $0.effectiveScheduledTime }
            .map { (time: $0.key, doses: $0.value.sorted { ($0.medication?.name ?? "") < ($1.medication?.name ?? "") }) }
            .sorted { $0.time < $1.time }
    }

    // Logged (taken/missed/skipped) in the last 24 h, most recent first
    private var recentHistory: [DoseEvent] {
        let cutoff = Date().addingTimeInterval(-86400)
        return allDoses.filter {
            ($0.status == .taken || $0.status == .missed || $0.status == .skipped)
            && ($0.loggedTime ?? $0.effectiveScheduledTime) >= cutoff
        }
        .sorted { ($0.loggedTime ?? $0.effectiveScheduledTime) > ($1.loggedTime ?? $1.effectiveScheduledTime) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if todayDoses.isEmpty && recentHistory.isEmpty {
                    ScrollView {
                        VStack(spacing: 20) { streakBanner; refillBanner; emptyState }
                            .padding().padding(.bottom, 32)
                    }
                } else {
                    List {
                        Section {
                            streakBanner
                            refillBanner
                        }
                        .plainCardRow()

                        if todayDoses.isEmpty {
                            Section { emptyState }.plainCardRow()
                        } else {
                            ForEach(todayGroups, id: \.time) { group in
                                Section {
                                    ForEach(group.doses) { dose in
                                        DoseCardView(dose: dose, onQuickLog: { quickLog(dose) })
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedDose = dose }
                                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                                Button { quickLog(dose) } label: {
                                                    Label("Take", systemImage: "checkmark.circle.fill")
                                                }.tint(Color.doseSage)
                                            }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) { skip(dose) } label: {
                                                    Label("Skip", systemImage: "minus.circle")
                                                }
                                                Button { selectedDose = dose } label: {
                                                    Label("Time", systemImage: "clock")
                                                }.tint(.blue)
                                            }
                                    }
                                } header: {
                                    timeSlotHeader(group).textCase(nil)
                                }
                                .plainCardRow()
                            }
                        }

                        if !recentHistory.isEmpty {
                            Section {
                                ForEach(recentHistory) { dose in
                                    HistoryRowView(dose: dose)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedDose = dose }
                                }
                            } header: {
                                sectionHeader("Last 24 hours", trailing: AnyView(
                                    Button("View all") { showAllHistory = true }
                                        .font(.subheadline).foregroundStyle(Color.doseSage)
                                )).textCase(nil)
                            }
                            .plainCardRow()
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.doseBackground)
            .navigationTitle(todayTitle)
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showAllHistory) {
                AllHistoryView()
            }
        }
        .sheet(item: $selectedDose) { dose in
            DoseActionSheet(dose: dose, onAction: { selectedDose = nil })
        }
        .overlay(milestoneOverlay)
    }

    // MARK: - Time-slot header + batch logging

    @ViewBuilder
    private func timeSlotHeader(_ group: (time: Date, doses: [DoseEvent])) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.time, format: .dateTime.hour().minute())
                .font(.headline)
            Text("· \(group.doses.count) med\(group.doses.count == 1 ? "" : "s")")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if group.doses.count >= 2 {
                Button {
                    takeAll(group.doses)
                } label: {
                    Label("Take all", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(Color.doseSage)
            }
        }
        .padding(.top, 4)
    }

    private func quickLog(_ dose: DoseEvent) {
        let store = MedicationStore(modelContext: modelContext)
        try? store.logDose(dose, at: Date())
        cancelNotifications(for: [dose])
    }

    private func skip(_ dose: DoseEvent) {
        let store = MedicationStore(modelContext: modelContext)
        try? store.skipDose(dose)
        cancelNotifications(for: [dose])
    }

    private func takeAll(_ doses: [DoseEvent]) {
        let store = MedicationStore(modelContext: modelContext)
        let logged = (try? store.logDoses(doses, at: Date())) ?? []
        cancelNotifications(for: logged)
    }

    /// Wipe every pending reminder (at-time, pre-alert, follow-ups, night alarm)
    /// for each recorded dose, so logging stops the nagging immediately.
    private func cancelNotifications(for doses: [DoseEvent]) {
        let ids = doses.map(\.id)
        Task {
            for id in ids {
                await NotificationService.shared.cancel(doseID: id)
            }
        }
        // Keep the Watch's list in step with logging done on the phone.
        PhoneConnectivityService.shared.syncTodayToWatch()
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, trailing: AnyView? = nil) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            trailing
        }
    }

    private var streakBanner: some View {
        let week = AdherenceCalculator.rolling7Day(for: allDoses)
        let allT = AdherenceCalculator.allTime(for: allDoses)
        return HStack {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            Text("\(allT.currentStreak) day streak").fontWeight(.semibold)
            Spacer()
            Text("\(Int(week.adherencePercent))% this week")
                .foregroundStyle(.secondary).font(.subheadline)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // Medications low on supply (only those actively tracking inventory).
    private var lowStockMeds: [Medication] {
        medications.filter { $0.isActive && $0.isLowOnSupply }
            .sorted { $0.daysOfSupplyRemaining ?? 0 < $1.daysOfSupplyRemaining ?? 0 }
    }

    @ViewBuilder
    private var refillBanner: some View {
        if !lowStockMeds.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Time to refill", systemImage: "pills.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(lowStockMeds) { med in
                    HStack {
                        Circle().fill(Color.fromHex(med.colorHex)).frame(width: 8, height: 8)
                        Text(med.name).font(.subheadline)
                        Spacer()
                        Text(med.supplyRemainingLabel)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.30), lineWidth: 1))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48)).foregroundStyle(Color.doseSage)
            Text("Nothing scheduled today").font(.title3.weight(.medium))
            Text("Add a medication to get started.").foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var todayTitle: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f.string(from: Date())
    }

    @ViewBuilder
    private var milestoneOverlay: some View {
        if let streak = showMilestone {
            MilestoneBanner(streak: streak) { withAnimation { showMilestone = nil } }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
        }
    }
}

// MARK: - List row styling

private extension View {
    /// Card-style list row: transparent background, no separators, comfortable insets.
    func plainCardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

// MARK: - DoseCardView

struct DoseCardView: View {
    var dose: DoseEvent
    var onQuickLog: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(medColor)
                .frame(width: 44, height: 44)
                .overlay { Image(systemName: "pill.fill").foregroundStyle(.white) }

            VStack(alignment: .leading, spacing: 4) {
                Text(dose.medication?.name ?? "Unknown").font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    Text(timeLabel).font(.subheadline).foregroundStyle(.secondary)
                    if dose.status == .pending && !dose.isPast {
                        Text("·").foregroundStyle(.secondary)
                        Text(dose.effectiveScheduledTime, style: .relative)
                            .font(.subheadline).foregroundStyle(Color.doseSage)
                    }
                }
            }

            Spacer()
            statusBadge
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 1.5)
        )
    }

    private var medColor: Color { Color.fromHex(dose.medication?.colorHex ?? "#7B9E87") }

    private var borderColor: Color {
        switch dose.status {
        case .missed: return .red.opacity(0.35)
        case .pending where dose.isPast: return Color.doseSage.opacity(0.4)
        default: return .clear
        }
    }

    private var timeLabel: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: dose.effectiveScheduledTime)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch dose.status {
        case .pending:
            // One-tap "taken" — the primary quick action, Apple-Health style.
            Button {
                onQuickLog?()
            } label: {
                Image(systemName: "checkmark.circle\(dose.isPast ? ".fill" : "")")
                    .font(.system(size: 30))
                    .foregroundStyle(dose.isPast ? Color.doseSage : Color.doseSage.opacity(0.5))
                    .symbolRenderingMode(.hierarchical)
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Log \(dose.medication?.name ?? "dose") as taken")
        case .taken:
            Label("Taken", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.doseSage).font(.subheadline.weight(.medium))
        case .missed:
            Label("Missed", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red).font(.subheadline.weight(.medium))
        case .skipped:
            Label("Skipped", systemImage: "minus.circle.fill")
                .foregroundStyle(.secondary).font(.subheadline.weight(.medium))
        }
    }
}

// MARK: - HistoryRowView (compact, for the last-24h list)

struct HistoryRowView: View {
    let dose: DoseEvent

    var body: some View {
        HStack(spacing: 12) {
            // Colour dot
            Circle()
                .fill(Color.fromHex(dose.medication?.colorHex ?? "#7B9E87"))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(dose.medication?.name ?? "Unknown")
                    .font(.subheadline.weight(.medium))
                if let logged = dose.loggedTime {
                    Text("Logged \(logged, style: .time)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Scheduled \(dose.effectiveScheduledTime, style: .time)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusChip
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch dose.status {
        case .taken:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("\(Int(dose.score))%")
            }
            .font(.caption.bold())
            .foregroundStyle(Color.doseSage)
        case .missed:
            Label("Missed", systemImage: "exclamationmark.circle.fill")
                .font(.caption.bold()).foregroundStyle(.red)
        case .skipped:
            Label("Skipped", systemImage: "minus.circle.fill")
                .font(.caption.bold()).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

// MARK: - AllHistoryView

struct AllHistoryView: View {
    @Query(sort: \DoseEvent.effectiveScheduledTime, order: .reverse) private var allDoses: [DoseEvent]
    @State private var selectedDose: DoseEvent?

    private var loggedDoses: [DoseEvent] {
        allDoses.filter { $0.status == .taken || $0.status == .missed || $0.status == .skipped }
    }

    // Group by calendar day
    private var grouped: [(String, [DoseEvent])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateStyle = .medium; fmt.timeStyle = .none

        var dict: [(key: Date, value: [DoseEvent])] = []
        for dose in loggedDoses {
            let day = cal.startOfDay(for: dose.effectiveScheduledTime)
            if let idx = dict.firstIndex(where: { $0.key == day }) {
                dict[idx].value.append(dose)
            } else {
                dict.append((key: day, value: [dose]))
            }
        }
        return dict
            .sorted { $0.key > $1.key }
            .map { (fmt.string(from: $0.key), $0.value) }
    }

    var body: some View {
        Group {
            if loggedDoses.isEmpty {
                ContentUnavailableView("No history yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Logged doses will appear here."))
            } else {
                List {
                    ForEach(grouped, id: \.0) { day, doses in
                        Section(day) {
                            ForEach(doses) { dose in
                                Button {
                                    selectedDose = dose
                                } label: {
                                    HistoryRowView(dose: dose)
                                        .listRowInsets(EdgeInsets())
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Dose History")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedDose) { dose in
            DoseActionSheet(dose: dose, onAction: { selectedDose = nil })
        }
    }
}

// MARK: - DoseActionSheet

struct DoseActionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var dose: DoseEvent
    let onAction: () -> Void

    @State private var note = ""
    @State private var showBackdate = false
    @State private var backdateTime = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Circle()
                        .fill(Color.fromHex(dose.medication?.colorHex ?? "#7B9E87"))
                        .frame(width: 56, height: 56)
                        .overlay { Image(systemName: "pill.fill").foregroundStyle(.white).font(.title3) }
                    Text(dose.medication?.name ?? "Dose")
                        .font(.title2.bold())
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text("Scheduled \(dose.effectiveScheduledTime, style: .time) · \(dose.effectiveScheduledTime, style: .date)")
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    statusLabel
                }
                .padding(.top, 24).padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(Color.doseBackground)

                Form {
                    if dose.status != .skipped {
                        Section("Note (optional)") {
                            TextField("e.g. Took with dinner", text: $note, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }

                    switch dose.status {
                    case .pending, .missed:
                        Section {
                            Button {
                                logNow(at: Date())
                            } label: {
                                Label(
                                    dose.status == .missed ? "Record anyway — log now" : "Log now",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .foregroundStyle(Color.doseSage)
                            }
                            Button {
                                backdateTime = dose.effectiveScheduledTime
                                showBackdate = true
                            } label: {
                                Label("Log at a different time…", systemImage: "clock.arrow.circlepath")
                                    .foregroundStyle(.primary)
                            }
                            if dose.status == .pending {
                                Button(role: .destructive) { skipDose() } label: {
                                    Label("Skip this dose", systemImage: "minus.circle")
                                }
                            }
                        }
                    case .taken:
                        Section {
                            if let logged = dose.loggedTime {
                                LabeledContent("Logged at", value: logged, format: .dateTime.hour().minute())
                            }
                            LabeledContent("Score", value: "\(Int(dose.score))%")
                        }
                    case .skipped:
                        Section {
                            Text("This dose was skipped.").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Dose details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showBackdate) { backdateSheet }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch dose.status {
        case .pending:
            Label(dose.isPast ? "Overdue" : "Scheduled",
                  systemImage: dose.isPast ? "exclamationmark.clock" : "clock")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(dose.isPast ? Color.orange.opacity(0.15) : Color.doseSage.opacity(0.15), in: Capsule())
                .foregroundStyle(dose.isPast ? .orange : Color.doseSage)
        case .taken:
            Label("Taken", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.doseSage.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.doseSage)
        case .missed:
            Label("Missed — tap to record", systemImage: "exclamationmark.circle.fill")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.red.opacity(0.12), in: Capsule())
                .foregroundStyle(.red)
        case .skipped:
            Label("Skipped", systemImage: "minus.circle.fill")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }

    private var backdateSheet: some View {
        NavigationStack {
            DatePicker("Time taken", selection: $backdateTime,
                       in: dose.effectiveScheduledTime.addingTimeInterval(-3600 * 12)...Date(),
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
                .navigationTitle("When did you take it?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showBackdate = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Log") { logNow(at: backdateTime); showBackdate = false }
                    }
                }
        }
    }

    private func logNow(at time: Date) {
        let store = MedicationStore(modelContext: modelContext)
        try? store.logDose(dose, at: time)
        dose.note = note.isEmpty ? nil : note
        try? store.save()
        let id = dose.id
        Task { await NotificationService.shared.cancel(doseID: id) }
        dismiss()
    }

    private func skipDose() {
        let store = MedicationStore(modelContext: modelContext)
        try? store.skipDose(dose)
        let id = dose.id
        Task { await NotificationService.shared.cancel(doseID: id) }
        dismiss()
    }
}

// MARK: - MilestoneBanner

struct MilestoneBanner: View {
    let streak: Int
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("Nice — \(streak) days in a row.").font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark").foregroundStyle(.secondary) }
            }
            .padding()
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding()
            Spacer()
        }
    }
}
