import SwiftUI
import SwiftData

struct TripsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            if !plannedTrips.isEmpty {
                                tripSection("Planned travel", trips: plannedTrips)
                            }
                            if !previousTrips.isEmpty {
                                tripSection("Previous travel", trips: previousTrips)
                            }
                        }
                        .padding()
                        .padding(.bottom, 32)
                    }
                    .background(Color.doseBackground)
                }
            }
            .navigationTitle("Travel")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddTripView() }
    }

    private func tripSection(_ title: String, trips: [Trip]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ForEach(trips) { trip in
                NavigationLink {
                    TripDetailView(trip: trip)
                } label: {
                    TripCardView(trip: trip)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 52))
                .foregroundStyle(Color.doseSage)
            Text("No trips yet").font(.title3.weight(.semibold))
            Text("Plan a trip and Doseify will gently migrate your dose times across timezones — protecting your sleep along the way.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label("Plan a trip", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.doseSage, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.doseBackground)
    }

    private var plannedTrips: [Trip] {
        trips.filter { $0.status != .cancelled && $0.endDate >= Date() }
    }

    private var previousTrips: [Trip] {
        trips.filter { $0.status == .cancelled || $0.endDate < Date() }
    }
}

// MARK: - Trip card

struct TripCardView: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(displayName)
                    .font(.headline)
                Spacer()
                statusBadge
            }

            // Route line: home → destination
            HStack(spacing: 8) {
                Image(systemName: "house.fill").font(.caption).foregroundStyle(.secondary)
                routeLine
                Image(systemName: "mappin.circle.fill").font(.caption).foregroundStyle(Color.doseSage)
            }

            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption).foregroundStyle(.secondary)
                Text("\(dateStr(trip.startDate)) – \(dateStr(trip.endDate))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                chip(trip.shiftStrategy.rawValue.capitalized, systemImage: "slider.horizontal.3")
                chip(cityName(trip.destinationTimezone), systemImage: "globe")
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var routeLine: some View {
        ZStack {
            Capsule().fill(Color.doseSage.opacity(0.25)).frame(height: 2)
            Image(systemName: "airplane")
                .font(.caption2)
                .foregroundStyle(Color.doseSage)
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.doseSlate.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.doseSlate)
            .lineLimit(1)
    }

    private var displayName: String {
        trip.name.isEmpty ? cityName(trip.destinationTimezone) : trip.name
    }

    private var statusBadge: some View {
        Text(displayStatus.label)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(displayStatus.color.opacity(0.15), in: Capsule())
            .foregroundStyle(displayStatus.color)
    }

    private enum DisplayStatus {
        case upcoming, active, completed, cancelled
        var label: String {
            switch self {
            case .upcoming: return "Upcoming"
            case .active: return "Active"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            }
        }
        var color: Color {
            switch self {
            case .active: return .doseSage
            case .upcoming: return .doseSlate
            case .completed: return .secondary
            case .cancelled: return .red
            }
        }
    }

    private var displayStatus: DisplayStatus {
        if trip.status == .cancelled { return .cancelled }
        let now = Date()
        if now < trip.startDate { return .upcoming }
        if now <= trip.endDate { return .active }
        return .completed
    }

    private func dateStr(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date)
    }
}

/// "Asia/Tokyo" → "Tokyo". Shared helper for trip displays.
func cityName(_ tzID: String) -> String {
    tzID.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tzID
}

// MARK: - Searchable timezone picker

struct TimezonePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var query = ""

    private var matches: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            ForEach(matches, id: \.self) { id in
                Button {
                    selection = id
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cityName(id)).foregroundStyle(.primary)
                            Text(id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(offsetLabel(id)).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if id == selection {
                            Image(systemName: "checkmark").foregroundStyle(Color.doseSage)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search city or region")
        .navigationTitle("Destination")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func offsetLabel(_ id: String) -> String {
        guard let tz = TimeZone(identifier: id) else { return "" }
        let secs = tz.secondsFromGMT()
        let sign = secs >= 0 ? "+" : "-"
        let h = abs(secs) / 3600, m = (abs(secs) % 3600) / 60
        return m == 0 ? "GMT\(sign)\(h)" : String(format: "GMT\(sign)%d:%02d", h, m)
    }
}

// MARK: - Add trip

struct AddTripView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query private var settingsList: [UserSettings]

    @State private var name = ""
    @State private var destinationTZ = "Asia/Tokyo"

    @State private var outDeparture = AddTripView.defaultDate(daysFromNow: 7, hour: 10)
    @State private var outArrival = AddTripView.defaultDate(daysFromNow: 7, hour: 18)
    @State private var retDeparture = AddTripView.defaultDate(daysFromNow: 21, hour: 10)
    @State private var retArrival = AddTripView.defaultDate(daysFromNow: 21, hour: 18)

    @State private var strategy: ShiftStrategy = .smart
    @State private var preShiftEnabled = true

    private var homeTZ: TimeZone {
        TimeZone(identifier: settingsList.first?.homeTimezone ?? TimeZone.current.identifier) ?? .current
    }
    private var destTZ: TimeZone { TimeZone(identifier: destinationTZ) ?? .current }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Name (optional)", text: $name)
                    NavigationLink {
                        TimezonePickerView(selection: $destinationTZ)
                    } label: {
                        HStack {
                            Text("Destination")
                            Spacer()
                            Text(cityName(destinationTZ)).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    flightPicker("Departs \(homeTZ.abbreviation() ?? "home")", selection: $outDeparture)
                    flightPicker("Arrives \(destTZ.abbreviation() ?? "dest")", selection: $outArrival)
                } header: {
                    Label("Outbound flight", systemImage: "airplane.departure")
                } footer: {
                    Text("Times are local to each airport. A dose that falls mid-flight stays on your departure timezone until you land.")
                }

                Section {
                    flightPicker("Departs \(destTZ.abbreviation() ?? "dest")", selection: $retDeparture)
                    flightPicker("Arrives \(homeTZ.abbreviation() ?? "home")", selection: $retArrival)
                } header: {
                    Label("Return flight", systemImage: "airplane.arrival")
                }

                Section {
                    Picker("Strategy", selection: $strategy) {
                        ForEach(ShiftStrategy.allCases, id: \.self) { s in
                            Text(s.rawValue.capitalized).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(previewMode.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Start adjusting before departure", isOn: $preShiftEnabled)
                } header: {
                    Text("Shift strategy")
                }

                if !medications.isEmpty {
                    Section("Preview") { previewCard }
                }

                Section {
                    Label(
                        "These timing adjustments are indicative only. Confirm any changes to your medication schedule with your doctor before traveling.",
                        systemImage: "stethoscope"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Plan a Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
        }
    }

    private func flightPicker(_ label: String, selection: Binding<Date>) -> some View {
        DatePicker(label, selection: selection, displayedComponents: [.date, .hourAndMinute])
    }

    // MARK: Preview

    private var previewSchedule: TripSchedule {
        TimezoneShiftEngine.computeTrip(
            trip: buildTrip(), medications: Array(medications),
            userSettings: previewSettings(), existingOverrides: []
        )
    }

    private var previewMode: ShiftMode {
        TimezoneShiftEngine.targetMode(strategy: strategy, daysAtDestination: buildTrip().daysAtDestination)
    }

    @ViewBuilder
    private var previewCard: some View {
        let schedule = previewSchedule
        VStack(alignment: .leading, spacing: 10) {
            Text(schedule.summary.headline)
                .font(.subheadline.weight(.medium))
            if schedule.summary.mode == .fullShift {
                Label("Aiming for \(schedule.summary.targetDestinationAnchor.displayString) local · reaching about \(schedule.summary.achievedDestinationAnchor.displayString)",
                      systemImage: "target")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(schedule.warnings) { warning in
                Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(warning.isAdvisory ? Color.secondary : Color.orange)
            }

            Divider()
            dayByDay(schedule)
        }
        .padding(.vertical, 4)
    }

    /// Compact day-by-day ramp so you can visualise the shift before saving.
    /// Shows the earliest dose each day with its badge; full per-dose detail and
    /// tap-to-override live in the trip detail screen after saving.
    @ViewBuilder
    private func dayByDay(_ schedule: TripSchedule) -> some View {
        let days = TripScheduleLayout.days(from: schedule, medications: Array(medications), homeTZ: homeTZ)
        let shown = Array(days.prefix(24))
        Text("Day by day")
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(shown) { day in
            if let row = day.rows.first {
                HStack(spacing: 8) {
                    Text(TripTimeFormat.dayTitle(day.day, tz: homeTZ))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    Image(systemName: row.badge.iconName)
                        .font(.caption2).foregroundStyle(row.badge.color)
                    Text(TripTimeFormat.clockShort(row.time, tzID: row.tzID))
                        .font(.caption.monospacedDigit().weight(.medium))
                    if day.rows.count > 1 {
                        Text("+\(day.rows.count - 1)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(TimeZone(identifier: row.tzID)?.abbreviation() ?? "")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        if days.count > shown.count {
            Text("+ \(days.count - shown.count) more days")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: Build

    private func previewSettings() -> UserSettings {
        let s = settingsList.first ?? UserSettings()
        return s
    }

    private func buildTrip() -> Trip {
        let outbound = Flight(
            departureDateTime: reinterpret(outDeparture, into: homeTZ), departureTimezone: homeTZ.identifier,
            arrivalDateTime: reinterpret(outArrival, into: destTZ), arrivalTimezone: destTZ.identifier
        )
        let ret = Flight(
            departureDateTime: reinterpret(retDeparture, into: destTZ), departureTimezone: destTZ.identifier,
            arrivalDateTime: reinterpret(retArrival, into: homeTZ), arrivalTimezone: homeTZ.identifier
        )
        return Trip(name: name, destinationTimezone: destinationTZ, shiftStrategy: strategy,
                    preShiftEnabled: preShiftEnabled, outboundFlight: outbound, returnFlight: ret)
    }

    private func save() {
        let trip = buildTrip()
        let store = MedicationStore(modelContext: modelContext)
        try? store.addTrip(trip)
        dismiss()
    }

    /// Reinterpret the wall-clock the user picked (shown in device-local time) as
    /// being in `tz`, so "10:00 departs London" means 10:00 *London* time.
    private func reinterpret(_ date: Date, into tz: TimeZone) -> Date {
        var dev = Calendar(identifier: .iso8601); dev.timeZone = .current
        let c = dev.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var target = Calendar(identifier: .iso8601); target.timeZone = tz
        return target.date(from: c) ?? date
    }

    private static func defaultDate(daysFromNow: Int, hour: Int) -> Date {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
        let day = cal.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }
}
