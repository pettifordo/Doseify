import SwiftUI

// Presentation helpers shared across the trip-planner UI. Keeps the engine's
// value types (ShiftBadge, ShiftMode, TripWarning, TripScheduleSummary) free of
// any UI concerns while giving the views one source of truth for labels/colors.

extension ShiftBadge {
    var label: String {
        switch self {
        case .stable: return "On schedule"
        case .shifting: return "Shifting"
        case .manualOverride: return "Edited"
        case .inFlight: return "In flight"
        case .skipped: return "Skip"
        }
    }

    var iconName: String {
        switch self {
        case .stable: return "checkmark.circle.fill"
        case .shifting: return "arrow.right.circle.fill"
        case .manualOverride: return "hand.tap.fill"
        case .inFlight: return "airplane.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .stable: return .doseSage
        case .shifting: return .doseSlate
        case .manualOverride: return .purple
        case .inFlight: return .blue
        case .skipped: return .orange
        }
    }
}

extension ShiftMode {
    var label: String {
        switch self {
        case .fullShift: return "Full shift"
        case .preserveAnchor: return "Keep home time"
        case .snapOnArrival: return "Snap on arrival"
        }
    }

    var explanation: String {
        switch self {
        case .fullShift:
            return "Your dose times migrate gradually toward destination local time."
        case .preserveAnchor:
            return "Your trip is short, so doses stay on home body-time — the local clock time may look unusual."
        case .snapOnArrival:
            return "Doses jump straight to destination time when you land."
        }
    }
}

extension ShiftDirection {
    var pathLabel: String {
        switch self {
        case .short: return "short path"
        case .long: return "long way round"
        }
    }
}

extension TripWarning: Identifiable {
    var id: String { message }

    var message: String {
        switch self {
        case .couldNotFullyShift(let achieved, let needed):
            return "This trip is too short to fully shift at your current rate — reaches about \(fmt(achieved))h of the \(fmt(needed))h needed. You can raise the per-drug shift rate to close the gap."
        case .dosesSkippedForRealignment(let count):
            return "\(count) dose\(count == 1 ? " is" : "s are") skipped on the flight to keep a safe gap between doses (at most one each way)."
        case .tripTooShortForGradualShift:
            return "Stay is under 7 days, so Doseify keeps your home schedule. Choose an immediate shift if you'd rather adjust on arrival."
        case .bidSpacingViolated:
            return "Some doses fall closer together than the safe minimum and a single skip can't fix it — please review this trip with your doctor."
        }
    }

    var isAdvisory: Bool {
        if case .dosesSkippedForRealignment = self { return true }
        return false
    }

    private func fmt(_ h: Double) -> String { String(format: "%.1f", h) }
}

extension TripScheduleSummary {
    /// One-line human summary in the spirit of SPEC §2.4.7.
    var headline: String {
        switch mode {
        case .preserveAnchor:
            return "Keeping your home schedule for this trip."
        case .snapOnArrival:
            return "Snapping to destination time on arrival — about \(shiftText) of change."
        case .fullShift:
            var s = "Shifting \(shiftText) toward destination time, following your body clock."
            if skippedDoseCount > 0 {
                s += " \(skippedDoseCount) dose\(skippedDoseCount == 1 ? "" : "s") skipped to avoid an overdose."
            }
            return s
        }
    }

    var shiftText: String {
        let whole = Int(shiftMagnitudeHours)
        let mins = Int((shiftMagnitudeHours - Double(whole)) * 60 + 0.5)
        if mins == 0 { return "\(whole)h" }
        return "\(whole)h \(mins)m"
    }
}

// MARK: - Flattened schedule for day-by-day display

/// One dose occurrence flattened out of the engine's grouped schedule, ready for
/// a row in the day-by-day views (planner preview + trip detail).
struct ScheduleRow: Identifiable {
    let id: String
    let groupId: UUID
    let groupName: String
    let scheduledDay: Date
    /// Home minutes-from-midnight of this dose's slot — identifies which of the
    /// day's doses this is, so overrides target exactly one dose.
    let slotMinutes: Int
    let time: Date
    let tzID: String
    let badge: ShiftBadge
    let context: LocationContext
    let isOverride: Bool
    /// Interval since the group's previous dose (nil for the first dose shown).
    let gapFromPrevious: TimeInterval?

    /// "12h 30m since last dose" — makes the shift engine's spacing visible.
    var gapLabel: String? {
        guard let gap = gapFromPrevious else { return nil }
        let totalMinutes = Int((gap / 60).rounded())
        let h = totalMinutes / 60, m = totalMinutes % 60
        return m == 0 ? "\(h)h since last dose" : "\(h)h \(m)m since last dose"
    }

    var contextLabel: String {
        switch context {
        case .home: return "Home"
        case .preShifting: return "Pre-shift at home"
        case .inFlightOutbound: return "In flight (outbound)"
        case .destinationShifting: return "Destination — adjusting"
        case .destinationStable: return "Destination"
        case .inFlightReturn: return "In flight (return)"
        case .postReturn: return "Back home — unwinding"
        case .layover: return "Layover"
        }
    }
}

struct ScheduleDay: Identifiable {
    let day: Date
    let rows: [ScheduleRow]
    var id: Date { day }
}

enum TripScheduleLayout {
    /// Flatten the engine's grouped schedule into per-day rows, sorted by day then time.
    static func days(from schedule: TripSchedule, medications: [Medication], homeTZ: TimeZone) -> [ScheduleDay] {
        var homeCal = Calendar(identifier: .gregorian)
        homeCal.timeZone = homeTZ

        var rows: [ScheduleRow] = []
        for group in schedule.doseGroups {
            let groupName = group.medicationIDs
                .compactMap { id in medications.first { $0.id == id }?.name }
                .joined(separator: " + ")
            // Gap = spacing between this group's consecutive effective times
            // (skipped doses excluded — nothing is taken then).
            let ordered = group.entries
                .filter { !$0.isSkipped }
                .sorted { $0.effectiveTimeUTC < $1.effectiveTimeUTC }
            var previousTime: [String: Date] = [:]
            for (i, entry) in ordered.enumerated() where i > 0 {
                previousTime["\(entry.effectiveTimeUTC.timeIntervalSince1970)"] = ordered[i - 1].effectiveTimeUTC
            }
            for entry in group.entries {
                let comps = homeCal.dateComponents([.hour, .minute], from: entry.scheduledTimeHomeUTC)
                let slot = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                let prev = previousTime["\(entry.effectiveTimeUTC.timeIntervalSince1970)"]
                rows.append(ScheduleRow(
                    id: "\(group.groupId)-\(entry.effectiveTimeUTC.timeIntervalSince1970)",
                    groupId: group.groupId,
                    groupName: groupName.isEmpty ? "Dose" : groupName,
                    scheduledDay: entry.day,
                    slotMinutes: slot,
                    time: entry.effectiveTimeUTC,
                    tzID: entry.effectiveTimezone,
                    badge: entry.badge,
                    context: entry.context,
                    isOverride: entry.isManualOverride,
                    gapFromPrevious: entry.isSkipped ? nil : prev.map { entry.effectiveTimeUTC.timeIntervalSince($0) }
                ))
            }
        }
        let byDay = Dictionary(grouping: rows) { TimezoneShiftEngine.startOfDay($0.scheduledDay, tz: homeTZ) }
        return byDay.keys.sorted().map { day in
            ScheduleDay(day: day, rows: byDay[day]!.sorted { $0.time < $1.time })
        }
    }
}

enum TripTimeFormat {
    /// "8:30 AM JST" — wall-clock time of `instant` in the given timezone.
    static func clock(_ instant: Date, tzID: String) -> String {
        let tz = TimeZone(identifier: tzID) ?? .current
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = tz
        let abbrev = tz.abbreviation(for: instant) ?? ""
        return abbrev.isEmpty ? f.string(from: instant) : "\(f.string(from: instant)) \(abbrev)"
    }

    static func clockShort(_ instant: Date, tzID: String) -> String {
        let tz = TimeZone(identifier: tzID) ?? .current
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = tz
        return f.string(from: instant)
    }

    static func dayTitle(_ day: Date, tz: TimeZone) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.timeZone = tz
        return f.string(from: day)
    }
}
