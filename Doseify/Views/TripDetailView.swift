import SwiftUI
import SwiftData

/// The polished trip schedule: a summary header, any warnings, and the per-day
/// dose schedule with badges. Tap any dose to override its time (SPEC §2.4.7).
struct TripDetailView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query private var allOverrides: [DoseOverride]
    @Query private var settingsList: [UserSettings]

    @State private var editingRow: ScheduleRow?

    private var homeTZ: TimeZone {
        TimeZone(identifier: settingsList.first?.homeTimezone ?? TimeZone.current.identifier) ?? .current
    }
    private var activeMedications: [Medication] { medications.filter { $0.isActive } }
    private var overrides: [DoseOverride] { allOverrides.filter { $0.tripId == trip.id } }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                routeHeader

                if activeMedications.isEmpty {
                    infoCard("No active medications", "Add a medication to see its travel schedule.")
                } else {
                    let schedule = computeSchedule()
                    summaryCard(schedule.summary)
                    ForEach(schedule.warnings) { warning in
                        warningCard(warning)
                    }
                    legend
                    let days = TripScheduleLayout.days(from: schedule, medications: medications, homeTZ: homeTZ)
                    ForEach(days) { group in
                        dayCard(group)
                    }
                    Text("Tap any dose to set a custom time. Edited doses survive later changes to your flights.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                disclaimer
            }
            .padding()
            .padding(.bottom, 32)
        }
        .background(Color.doseBackground)
        .navigationTitle(trip.name.isEmpty ? cityName(trip.destinationTimezone) : trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) { deleteTrip() } label: {
                        Label("Delete trip", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $editingRow) { row in
            DoseOverrideSheet(trip: trip, row: row, existing: existingOverride(for: row)) {
                editingRow = nil
            }
        }
    }

    // MARK: - Header

    private var routeHeader: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                endpoint(icon: "house.fill", title: "Home", subtitle: cityName(homeTZ.identifier))
                VStack(spacing: 2) {
                    Image(systemName: "airplane")
                        .foregroundStyle(Color.doseSage)
                    Text(durationLabel).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                endpoint(icon: "mappin.circle.fill", title: "Away", subtitle: cityName(trip.destinationTimezone))
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption).foregroundStyle(.secondary)
                Text("\(longDate(trip.startDate)) → \(longDate(trip.endDate))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func endpoint(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.doseSage)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(subtitle).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary

    private func summaryCard(_ s: TripScheduleSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").foregroundStyle(Color.doseSage)
                Text(s.mode.label).font(.headline)
            }
            Text(s.headline).font(.subheadline)
            if s.mode == .fullShift {
                HStack(spacing: 16) {
                    metric("Target", s.targetDestinationAnchor.displayString)
                    metric("Reaches", s.achievedDestinationAnchor.displayString)
                    if s.skippedDoseCount > 0 { metric("Skipped", "\(s.skippedDoseCount)") }
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.doseSage.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
    }

    private func warningCard(_ warning: TripWarning) -> some View {
        Label(warning.message, systemImage: warning.isAdvisory ? "info.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(warning.isAdvisory ? Color.doseSlate : .orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background((warning.isAdvisory ? Color.doseSlate : .orange).opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(legendBadges, id: \.self) { badge in
                    Label(badge.label, systemImage: badge.iconName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(badge.color.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private var legendBadges: [ShiftBadge] { [.stable, .shifting, .skipped, .inFlight, .manualOverride] }

    // MARK: - Day card

    private func dayCard(_ group: ScheduleDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TripTimeFormat.dayTitle(group.day, tz: homeTZ))
                .font(.subheadline.weight(.semibold))
            ForEach(group.rows) { row in
                Button { editingRow = row } label: { doseRow(row) }
                    .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }

    private func doseRow(_ row: ScheduleRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.badge.iconName)
                .foregroundStyle(row.badge.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.groupName).font(.subheadline.weight(.medium))
                Text(row.contextLabel).font(.caption).foregroundStyle(.secondary)
                if let gap = row.gapLabel {
                    Text(gap).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(TripTimeFormat.clockShort(row.time, tzID: row.tzID))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(badgeOrZone(row)).font(.caption2).foregroundStyle(row.badge.color)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func badgeOrZone(_ row: ScheduleRow) -> String {
        let zone = TimeZone(identifier: row.tzID)?.abbreviation() ?? ""
        return row.isOverride ? "Edited · \(zone)" : "\(row.badge.label) · \(zone)"
    }

    // MARK: - Schedule assembly

    private func computeSchedule() -> TripSchedule {
        let settings = settingsList.first ?? UserSettings(homeTimezone: homeTZ.identifier)
        // Same overlay MedicationStore uses for DoseEvents/notifications, so
        // the preview always shows the exact times that will fire.
        return DoseShiftV2Service.overlay(
            schedule: TimezoneShiftEngine.computeTrip(
                trip: trip, medications: activeMedications, userSettings: settings, existingOverrides: overrides
            ),
            trip: trip, medications: activeMedications, settings: settings
        )
    }

    private func existingOverride(for row: ScheduleRow) -> DoseOverride? {
        overrides.first {
            $0.shiftGroupId == row.groupId &&
            TimezoneShiftEngine.isSameDay($0.scheduledDate, row.scheduledDay, tz: homeTZ) &&
            ($0.slotMinutes == -1 || $0.slotMinutes == row.slotMinutes)
        }
    }

    private func deleteTrip() {
        let store = MedicationStore(modelContext: modelContext)
        try? store.deleteTrip(trip)
        guard let settings = try? store.settings() else { return }
        try? store.generateUpcomingDoses(settings: settings)
        if let inputs = try? store.notificationInputs() {
            Task {
                await NotificationService.shared.rescheduleAll(
                    doses: inputs.doses, medications: inputs.medications,
                    settings: inputs.settings, nightAlarmActive: inputs.nightAlarm
                )
            }
        }
        // Doses reverted to home times — keep the Watch in step.
        PhoneConnectivityService.shared.syncTodayToWatch()
    }

    // MARK: - Small pieces

    private func infoCard(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var disclaimer: some View {
        Label(
            "These timing adjustments are indicative only. Confirm any changes to your medication schedule with your doctor before traveling.",
            systemImage: "stethoscope"
        )
        .font(.caption).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationLabel: String {
        let days = max(0, Calendar(identifier: .iso8601).dateComponents([.day], from: trip.startDate, to: trip.endDate).day ?? 0)
        return "\(days)d"
    }

    private func longDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date)
    }
}

// MARK: - Override sheet

struct DoseOverrideSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    let row: ScheduleRow
    let existing: DoseOverride?
    let onDone: () -> Void

    @State private var picked: Date = Date()

    private var tz: TimeZone { TimeZone(identifier: row.tzID) ?? .current }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill").font(.title2).foregroundStyle(.purple)
                    Text(row.groupName).font(.title3.bold())
                    Text(TripTimeFormat.dayTitle(row.scheduledDay, tz: tz))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 24).padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(Color.doseBackground)

                Form {
                    Section {
                        DatePicker("Dose time", selection: $picked, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                    } header: {
                        Text("Custom time")
                    } footer: {
                        Text("Shown in \(cityName(row.tzID)) local time. This overrides Doseify's computed time for this dose only.")
                    }

                    if existing != nil {
                        Section {
                            Button(role: .destructive) { removeOverride() } label: {
                                Label("Remove custom time", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Adjust dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { close() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveOverride() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                picked = toPicker(existing?.customTimeUTC ?? row.time)
            }
        }
        .presentationDetents([.medium])
    }

    private func saveOverride() {
        let customUTC = fromPicker(picked)
        if let existing = existing {
            existing.customTimeUTC = customUTC
        } else {
            let ov = DoseOverride(
                tripId: trip.id, shiftGroupId: row.groupId,
                scheduledDate: row.scheduledDay, slotMinutes: row.slotMinutes,
                customTimeUTC: customUTC
            )
            modelContext.insert(ov)
        }
        try? modelContext.save()
        close()
    }

    private func removeOverride() {
        if let existing = existing { modelContext.delete(existing) }
        try? modelContext.save()
        close()
    }

    private func close() { dismiss(); onDone() }

    // Show/edit the time as wall-clock in the dose's timezone using a device-local picker.
    private func toPicker(_ utc: Date) -> Date {
        var tzCal = Calendar(identifier: .iso8601); tzCal.timeZone = tz
        let c = tzCal.dateComponents([.year, .month, .day, .hour, .minute], from: utc)
        var dev = Calendar(identifier: .iso8601); dev.timeZone = .current
        return dev.date(from: c) ?? utc
    }

    private func fromPicker(_ p: Date) -> Date {
        var dev = Calendar(identifier: .iso8601); dev.timeZone = .current
        let comps = dev.dateComponents([.hour, .minute], from: p)
        // Combine the picked hour/minute with the override's calendar day in the target tz.
        var tzCal = Calendar(identifier: .iso8601); tzCal.timeZone = tz
        var dayComps = tzCal.dateComponents([.year, .month, .day], from: dayInTZ())
        dayComps.hour = comps.hour
        dayComps.minute = comps.minute
        return tzCal.date(from: dayComps) ?? p
    }

    /// The override's calendar day, expressed in the dose timezone.
    private func dayInTZ() -> Date {
        // row.scheduledDay is a home-tz day marker; use the dose's actual instant
        // to land on the correct local calendar day at the destination.
        row.time
    }
}
