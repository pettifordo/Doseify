import Foundation

// MARK: - Public output types

/// The full computed schedule for a trip — what the preview UI renders and the
/// caller persists as `DoseEvent`s. Always returned (never thrown); problems
/// surface in `warnings`.
struct TripSchedule {
    let doseGroups: [DoseGroupSchedule]
    let warnings: [TripWarning]
    let summary: TripScheduleSummary
}

/// One dose group's (drugs that shift in lockstep) per-day schedule.
struct DoseGroupSchedule {
    let groupId: UUID
    let medicationIDs: [UUID]
    let entries: [ScheduledDose]
}

/// A single scheduled dose occurrence.
struct ScheduledDose {
    /// Home-anchored canonical time (UTC). CLAUDE.md hard rule 4: this is sacred.
    let scheduledTimeHomeUTC: Date
    /// Calendar day (home-tz start-of-day marker) this dose belongs to.
    let day: Date
    /// Absolute UTC instant the dose actually fires after shifting.
    let effectiveTimeUTC: Date
    /// IANA identifier of the timezone whose wall-clock this dose is anchored to.
    let effectiveTimezone: String
    let context: LocationContext
    let badge: ShiftBadge
    let isManualOverride: Bool
    /// True when this dose is skipped to keep a safe gap from the previous dose
    /// across a flight realignment (never skipped for sleep — see SPEC §2.4).
    let isSkipped: Bool

    /// A copy of this dose marked as skipped (badge updated for display).
    func markedSkipped() -> ScheduledDose {
        ScheduledDose(
            scheduledTimeHomeUTC: scheduledTimeHomeUTC, day: day,
            effectiveTimeUTC: effectiveTimeUTC, effectiveTimezone: effectiveTimezone,
            context: context, badge: .skipped, isManualOverride: isManualOverride, isSkipped: true
        )
    }
}

/// Outcome of simulating one direction's day-by-day trajectory.
struct Trajectory {
    let cumByDay: [CumulativeShiftDay]
    /// Number of days where the full daily increment would have landed in the
    /// forbidden window and was avoided (by a reduced increment or a hold).
    let breachCount: Int
    /// Number of days the shift was fully paused to stay out of the window.
    let heldDoseCount: Int
    /// Peak shift magnitude reached at the destination, in minutes.
    let totalShiftAchievedMinutes: Int
    let targetShiftMinutes: Int
    let direction: ShiftDirection
}

/// Cumulative shift (seconds, signed) applied to the home anchor on one day.
struct CumulativeShiftDay {
    let day: Date            // home-tz start-of-day marker
    let cumulativeSeconds: Int
    let held: Bool
    let reduced: Bool        // accepted a reduced increment to dodge the window
    let flightDay: Bool
}

struct TripScheduleSummary {
    let shiftMagnitudeHours: Double
    let directionChosen: ShiftDirection
    /// Doses skipped to avoid an overdose across a flight realignment (0, 1, or 2).
    let skippedDoseCount: Int
    let achievedDestinationAnchor: TimeOfDay
    let targetDestinationAnchor: TimeOfDay
    let mode: ShiftMode
}

enum TripWarning: Equatable {
    case couldNotFullyShift(achievedHours: Double, neededHours: Double)
    /// One or more doses are skipped across a flight to avoid an overdose (max 1 each way).
    case dosesSkippedForRealignment(count: Int)
    case tripTooShortForGradualShift(suggestedAlternative: ShiftStrategy)
    /// Doses would fall closer than the safe minimum and the single permitted
    /// skip per flight isn't enough — needs the user's attention.
    case bidSpacingViolated(date: Date)
}

enum ShiftDirection: Equatable { case short, long }
enum ShiftMode: Equatable { case fullShift, preserveAnchor, snapOnArrival }

enum LocationContext: Equatable {
    case home, preShifting, inFlightOutbound, destinationShifting, destinationStable, inFlightReturn, postReturn, layover
}

enum ShiftBadge: Equatable {
    case stable, shifting, manualOverride, inFlight, skipped
}

/// Interval (minutes from local midnight) in which no dose may be scheduled.
struct SleepWindow: Equatable {
    let startMinutesFromMidnight: Int    // 0..1440
    let endMinutesFromMidnight: Int      // 0..1440, may wrap

    init(startMinutesFromMidnight: Int, endMinutesFromMidnight: Int) {
        self.startMinutesFromMidnight = startMinutesFromMidnight
        self.endMinutesFromMidnight = endMinutesFromMidnight
    }

    /// Half-open `[start, end)` so a dose exactly at the window's end (e.g. 06:00) is allowed.
    func contains(localMinutes m: Int) -> Bool {
        if startMinutesFromMidnight == endMinutesFromMidnight { return false }
        if startMinutesFromMidnight < endMinutesFromMidnight {
            return m >= startMinutesFromMidnight && m < endMinutesFromMidnight
        }
        return m >= startMinutesFromMidnight || m < endMinutesFromMidnight
    }
}

// MARK: - Engine

/// Pure timezone-shift computation. Same inputs → same outputs, no side effects,
/// no SwiftData calls (this file imports `Foundation` only). The engine returns a
/// *proposal* the user can override before any notification fires (SPEC §2.4).
struct TimezoneShiftEngine {

    // INVARIANT: all day arithmetic uses an explicit timezone. The canonical
    // `scheduledTimeHome` is always derived in the home timezone; only display
    // and forbidden-window checks use the current location's timezone.

    private static let secondsPerHour = 3600
    private static let secondsPerDay = 86_400

    // MARK: Top-level entry point

    /// Compute the full per-dose schedule for a trip.
    static func computeTrip(
        trip: Trip,
        medications: [Medication],
        userSettings: UserSettings,
        existingOverrides: [DoseOverride]
    ) -> TripSchedule {

        let homeTZ = TimeZone(identifier: userSettings.homeTimezone) ?? .current
        let destTZ = TimeZone(identifier: trip.destinationTimezone) ?? homeTZ
        let sleep = SleepWindow(
            startMinutesFromMidnight: userSettings.sleepWindowStart.totalMinutes,
            endMinutesFromMidnight: userSettings.sleepWindowEnd.totalMinutes
        )

        // A trip with no flights, no medications, or zero delta → trivial schedule.
        guard let outbound = trip.outboundFlight,
              let returnFlight = trip.returnFlight,
              !medications.isEmpty else {
            return TripSchedule(
                doseGroups: [],
                warnings: [],
                summary: trivialSummary(homeTZ: homeTZ, destTZ: destTZ, mode: .preserveAnchor)
            )
        }

        let phases = TripPhases(
            outbound: outbound,
            returnFlight: returnFlight,
            layovers: trip.layovers.filter { $0.isIntermediateStay },
            homeTZ: homeTZ,
            destTZ: destTZ
        )

        // --- Step 1: shift requirement ---
        // Doses follow the body clock, so we always migrate the geographic short
        // way (fewest days, least disruption). The "long way round" only ever
        // existed to dodge the local sleep window, which we no longer do.
        let refDate = outbound.arrivalDateTime
        let tzDelta = signedOffset(destTZ, at: refDate) - signedOffset(homeTZ, at: refDate)
        let normalizedDelta = normalize(tzDelta)              // (-12h, +12h]
        let shortTarget = -normalizedDelta                     // UTC shift to recreate home anchor at dest

        // --- Step 2: target mode ---
        let mode = targetMode(strategy: trip.shiftStrategy, daysAtDestination: trip.daysAtDestination)
        let directionChosen: ShiftDirection = .short
        let chosenTarget = (mode == .preserveAnchor) ? 0 : shortTarget

        let allDoseTimes = medications.flatMap { $0.scheduledTimesOfDay }.sorted()
        let primaryAnchor = allDoseTimes.first ?? .morning
        let slowestRateMin = max(1, medications.map { $0.timezoneShiftMinutesPerDay }.filter { $0 > 0 }.min() ?? 30)

        let dayRange = enumerateDays(
            from: phases.scheduleStartDay(preShiftEnabled: trip.preShiftEnabled, mode: mode,
                                          targetSeconds: shortTarget, rateMinutes: slowestRateMin, tz: homeTZ),
            through: phases.scheduleEndDay(targetSeconds: shortTarget, rateMinutes: slowestRateMin, tz: homeTZ),
            tz: homeTZ
        )

        var warnings: [TripWarning] = []
        if mode == .preserveAnchor && trip.shiftStrategy == .smart && trip.daysAtDestination < 7 && shortTarget != 0 {
            warnings.append(.tripTooShortForGradualShift(suggestedAlternative: .immediate))
        }

        // Representative trajectory drives the summary (achieved anchor) and the
        // completion warning, describing one coherent trajectory.
        let repTraj = simulateCumulative(
            doseTimes: [primaryAnchor], rateMinutes: slowestRateMin, tripTarget: chosenTarget,
            direction: directionChosen, mode: mode, days: dayRange, phases: phases,
            homeTZ: homeTZ, sleep: sleep, preShiftEnabled: trip.preShiftEnabled
        )
        let signedPeakCum = repTraj.cumByDay.map { $0.cumulativeSeconds }.max(by: { abs($0) < abs($1) }) ?? 0

        // --- Build per-group schedules, then apply overdose-skip protection ---
        let groups = doseGroups(from: medications)
        var groupSchedules: [DoseGroupSchedule] = []
        var totalSkips = 0

        for group in groups {
            let groupRate = max(1, group.medications.map { $0.timezoneShiftMinutesPerDay }.filter { $0 > 0 }.min() ?? 30)
            let doseTimes = Array(Set(group.medications.flatMap { $0.scheduledTimesOfDay })).sorted()
            let minSpacingHours = group.medications.map { $0.minSpacingHours }.max() ?? 0

            let traj = simulateCumulative(
                doseTimes: doseTimes, rateMinutes: groupRate, tripTarget: chosenTarget,
                direction: directionChosen, mode: mode, days: dayRange, phases: phases,
                homeTZ: homeTZ, sleep: sleep, preShiftEnabled: trip.preShiftEnabled
            )

            let built = buildEntries(
                traj: traj, doseTimes: doseTimes, phases: phases, homeTZ: homeTZ,
                chosenTarget: chosenTarget, group: group, tripID: trip.id, overrides: existingOverrides
            )

            // Overdose protection: skip a dose only when realignment lands it within
            // the safe minimum gap of the previous one — at most one per flight.
            let skipResult = applyOverdoseSkips(
                entries: built, minSpacingSeconds: minSpacingHours * secondsPerHour,
                returnDeparture: returnFlight.departureDateTime
            )
            totalSkips += skipResult.skippedCount
            if let unsafeDay = skipResult.unsafeSpacingDay {
                warnings.append(.bidSpacingViolated(date: unsafeDay))
            }

            groupSchedules.append(DoseGroupSchedule(
                groupId: group.id,
                medicationIDs: group.medications.map { $0.id },
                entries: skipResult.entries
            ))
        }

        // --- Warnings derived from the chosen trajectory ---
        if totalSkips > 0 {
            warnings.append(.dosesSkippedForRealignment(count: totalSkips))
        }
        if mode == .fullShift && chosenTarget != 0 {
            let shortfall = repTraj.targetShiftMinutes - repTraj.totalShiftAchievedMinutes
            // Only flag a *material* shortfall — landing within ~90 min of the anchor
            // (e.g. 8:30 instead of 8:00) is acceptable, not worth alarming about.
            if shortfall > 90 {
                warnings.append(.couldNotFullyShift(
                    achievedHours: Double(repTraj.totalShiftAchievedMinutes) / 60.0,
                    neededHours: Double(repTraj.targetShiftMinutes) / 60.0
                ))
            }
        }

        let summary = buildSummary(
            mode: mode, directionChosen: directionChosen, chosenTarget: chosenTarget,
            peakCum: signedPeakCum, primaryAnchor: primaryAnchor,
            phases: phases, homeTZ: homeTZ,
            skippedDoseCount: totalSkips
        )

        return TripSchedule(doseGroups: groupSchedules, warnings: warnings, summary: summary)
    }

    // MARK: - Overdose-skip protection

    struct SkipResult {
        let entries: [ScheduledDose]
        let skippedCount: Int
        let unsafeSpacingDay: Date?   // spacing still unsafe after the 1-skip-per-flight cap
    }

    /// Skip a dose only when a flight realignment would place it closer than the
    /// safe minimum gap to the previously-kept dose. At most one skip on the way
    /// out and one on the way back (SPEC §2.4, per the product owner). If more
    /// skips would be needed, the dose is kept and the day is flagged for review.
    static func applyOverdoseSkips(entries: [ScheduledDose], minSpacingSeconds: Int, returnDeparture: Date) -> SkipResult {
        guard minSpacingSeconds > 0 else { return SkipResult(entries: entries, skippedCount: 0, unsafeSpacingDay: nil) }

        let ordered = entries.sorted { $0.effectiveTimeUTC < $1.effectiveTimeUTC }
        var out: [ScheduledDose] = []
        var lastKept: Date?
        var outboundSkipUsed = false
        var returnSkipUsed = false
        var skipped = 0
        var unsafeDay: Date?

        for entry in ordered {
            if let last = lastKept,
               entry.effectiveTimeUTC.timeIntervalSince(last) < Double(minSpacingSeconds),
               !entry.isManualOverride {
                let isReturnLeg = entry.effectiveTimeUTC > returnDeparture
                let canSkip = isReturnLeg ? !returnSkipUsed : !outboundSkipUsed
                if canSkip {
                    if isReturnLeg { returnSkipUsed = true } else { outboundSkipUsed = true }
                    skipped += 1
                    out.append(entry.markedSkipped())
                    continue   // skipped dose isn't taken, so it doesn't reset the spacing clock
                } else {
                    if unsafeDay == nil { unsafeDay = entry.day }
                }
            }
            out.append(entry)
            lastKept = entry.effectiveTimeUTC
        }
        return SkipResult(entries: out, skippedCount: skipped, unsafeSpacingDay: unsafeDay)
    }

    // MARK: Direction helper (exposed for testing)

    /// Choose the better of two simulated directions.
    ///
    /// INVARIANT: how close the dose ends up to the destination anchor matters
    /// more than avoiding a few holds. Completing *either* direction lands the dose
    /// on the same wall-clock anchor, so `targetShiftMinutes - totalShiftAchievedMinutes`
    /// (the minutes still needed to reach it) is directly comparable between the two
    /// — smaller means the dose lands nearer the target time. Ranking by this first
    /// stops the engine choosing the "long way round" just because the short way
    /// racks up harmless pre-shift holds while marching the dose to its target (the
    /// BST→Tokyo bug: 8h short, reaching 8 AM, must beat 16h long, stranded at
    /// midnight). Only on a tie do we compare disruption: fewer breaches, then fewer
    /// holds, then the geographic short way.
    static func pickBetter(_ a: Trajectory, _ b: Trajectory) -> Trajectory {
        let aRemaining = a.targetShiftMinutes - a.totalShiftAchievedMinutes
        let bRemaining = b.targetShiftMinutes - b.totalShiftAchievedMinutes
        if aRemaining != bRemaining { return aRemaining < bRemaining ? a : b }
        if a.breachCount != b.breachCount { return a.breachCount < b.breachCount ? a : b }
        if a.heldDoseCount != b.heldDoseCount { return a.heldDoseCount < b.heldDoseCount ? a : b }
        // Tie: prefer the short direction (closer to the actual delta).
        return a.direction == .short ? a : b
    }

    /// Simulate one direction's trajectory for a single anchor — pure helper for tests.
    static func simulateTrajectory(
        direction: ShiftDirection,
        ratePerDay: Int,
        homeAnchor: TimeOfDay,
        homeTimezone: TimeZone,
        destTimezone: TimeZone,
        sleepWindow: SleepWindow,
        outboundFlight: Flight,
        returnFlight: Flight,
        layovers: [Layover] = [],
        preShiftEnabled: Bool = true
    ) -> Trajectory {
        let phases = TripPhases(
            outbound: outboundFlight, returnFlight: returnFlight,
            layovers: layovers.filter { $0.isIntermediateStay },
            homeTZ: homeTimezone, destTZ: destTimezone
        )
        let refDate = outboundFlight.arrivalDateTime
        let tzDelta = signedOffset(destTimezone, at: refDate) - signedOffset(homeTimezone, at: refDate)
        let normalized = normalize(tzDelta)
        let shortTarget = -normalized
        let target = direction == .short
            ? shortTarget
            : (shortTarget == 0 ? 0 : (shortTarget > 0 ? shortTarget - secondsPerDay : shortTarget + secondsPerDay))

        let days = enumerateDays(
            from: phases.scheduleStartDay(preShiftEnabled: preShiftEnabled, mode: .fullShift,
                                          targetSeconds: target, rateMinutes: max(1, ratePerDay), tz: homeTimezone),
            through: phases.scheduleEndDay(targetSeconds: target, rateMinutes: max(1, ratePerDay), tz: homeTimezone),
            tz: homeTimezone
        )
        return simulateCumulative(
            doseTimes: [homeAnchor], rateMinutes: max(1, ratePerDay), tripTarget: target,
            direction: direction, mode: .fullShift, days: days, phases: phases,
            homeTZ: homeTimezone, sleep: sleepWindow, preShiftEnabled: preShiftEnabled
        )
    }

    // MARK: - Core simulation

    /// Day-by-day cumulative-shift trajectory.
    ///
    /// INVARIANT: doses follow the BODY clock. The shift ramps smoothly toward
    /// `tripTarget` (the short way) while away, then back toward 0 for the return.
    /// It is NEVER held or paused because the *local* clock would read an awkward
    /// hour — during a gradual shift the dose simply is the traveller's body-time,
    /// so there is no "sleep window" to dodge (SPEC §2.4, per the product owner).
    /// Overdose protection (skipping a dose whose realignment lands it too close to
    /// the previous one) is applied separately, after entries are built.
    static func simulateCumulative(
        doseTimes: [TimeOfDay],
        rateMinutes: Int,
        tripTarget: Int,
        direction: ShiftDirection,
        mode: ShiftMode,
        days: [Date],
        phases: TripPhases,
        homeTZ: TimeZone,
        sleep: SleepWindow,
        preShiftEnabled: Bool
    ) -> Trajectory {

        let rateSeconds = max(1, rateMinutes) * 60

        let returnRampStartDay = phases.returnRampStartDay(
            preShiftEnabled: preShiftEnabled, targetSeconds: tripTarget, rateMinutes: rateMinutes, tz: homeTZ
        )
        let snapStartDay = startOfDay(phases.outbound.arrivalDateTime, tz: homeTZ)

        var cum = 0
        var result: [CumulativeShiftDay] = []
        var peakCum = 0

        for day in days {
            // Active target for this day: trip target until the return ramp begins, then home (0).
            let activeTarget: Int
            switch mode {
            case .preserveAnchor:
                activeTarget = 0
            case .snapOnArrival:
                activeTarget = (day >= snapStartDay && day < returnRampStartDay) ? tripTarget : 0
            case .fullShift:
                activeTarget = day < returnRampStartDay ? tripTarget : 0
            }

            // During a flight the anchor stays on the originating timezone — don't
            // advance the shift while airborne.
            let isFlightDay = doseTimes.contains { tod in
                let eff = anchorInstant(tod, day: day, homeTZ: homeTZ).addingTimeInterval(TimeInterval(cum))
                return phases.outbound.contains(eff) || phases.returnFlight.contains(eff)
            }
            if isFlightDay {
                result.append(CumulativeShiftDay(day: day, cumulativeSeconds: cum, held: false, reduced: false, flightDay: true))
                continue
            }

            switch mode {
            case .preserveAnchor:
                cum = 0
            case .snapOnArrival:
                cum = activeTarget
            case .fullShift:
                if cum != activeTarget {
                    let dir = activeTarget > cum ? 1 : -1
                    cum += dir * min(rateSeconds, abs(activeTarget - cum))
                }
            }
            if abs(cum) > abs(peakCum) { peakCum = cum }
            result.append(CumulativeShiftDay(day: day, cumulativeSeconds: cum, held: false, reduced: false, flightDay: false))
        }

        return Trajectory(
            cumByDay: result,
            breachCount: 0,
            heldDoseCount: 0,
            totalShiftAchievedMinutes: abs(peakCum) / 60,
            targetShiftMinutes: abs(tripTarget) / 60,
            direction: direction
        )
    }

    // MARK: - Entry building

    private static func buildEntries(
        traj: Trajectory,
        doseTimes: [TimeOfDay],
        phases: TripPhases,
        homeTZ: TimeZone,
        chosenTarget: Int,
        group: DoseGroup,
        tripID: UUID,
        overrides: [DoseOverride]
    ) -> [ScheduledDose] {
        var entries: [ScheduledDose] = []

        for cumDay in traj.cumByDay {
            for tod in doseTimes {
                let homeInstant = anchorInstant(tod, day: cumDay.day, homeTZ: homeTZ)
                var effective = homeInstant.addingTimeInterval(TimeInterval(cumDay.cumulativeSeconds))
                let context = phases.context(
                    for: effective, cum: cumDay.cumulativeSeconds, target: chosenTarget, flightDay: cumDay.flightDay
                )
                let displayTZ = phases.displayTimezone(for: effective)
                var badge = badgeFor(context: context, cumDay: cumDay, cum: cumDay.cumulativeSeconds, target: chosenTarget)
                var isOverride = false
                var effectiveTZID = displayTZ.identifier

                // Step 7: manual override wins for this one dose.
                if let ov = overrides.first(where: {
                    $0.tripId == tripID && $0.shiftGroupId == group.id &&
                    isSameDay($0.scheduledDate, cumDay.day, tz: homeTZ)
                }) {
                    effective = ov.customTimeUTC
                    badge = .manualOverride
                    isOverride = true
                    effectiveTZID = phases.displayTimezone(for: effective).identifier
                }

                entries.append(ScheduledDose(
                    scheduledTimeHomeUTC: homeInstant,
                    day: cumDay.day,
                    effectiveTimeUTC: effective,
                    effectiveTimezone: effectiveTZID,
                    context: context,
                    badge: badge,
                    isManualOverride: isOverride,
                    isSkipped: false
                ))
            }
        }
        return entries.sorted { $0.effectiveTimeUTC < $1.effectiveTimeUTC }
    }

    private static func badgeFor(context: LocationContext, cumDay: CumulativeShiftDay, cum: Int, target: Int) -> ShiftBadge {
        if cumDay.flightDay { return .inFlight }
        if cum == target { return .stable }
        return .shifting
    }

    // MARK: - Dose groups

    struct DoseGroup { let id: UUID; let medications: [Medication] }

    /// Group by `shiftGroupId`; medications with nil id are independent singletons
    /// keyed by their own id (SPEC §2.4.1 / case 8).
    private static func doseGroups(from medications: [Medication]) -> [DoseGroup] {
        var shared: [UUID: [Medication]] = [:]
        var singletons: [DoseGroup] = []
        for med in medications {
            if let gid = med.shiftGroupId {
                shared[gid, default: []].append(med)
            } else {
                singletons.append(DoseGroup(id: med.id, medications: [med]))
            }
        }
        let sharedGroups = shared.map { DoseGroup(id: $0.key, medications: $0.value) }
        return (sharedGroups + singletons).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    // MARK: - Summary

    private static func buildSummary(
        mode: ShiftMode, directionChosen: ShiftDirection, chosenTarget: Int,
        peakCum: Int, primaryAnchor: TimeOfDay, phases: TripPhases, homeTZ: TimeZone, skippedDoseCount: Int
    ) -> TripScheduleSummary {
        // Achieved destination anchor = where the primary dose lands at peak shift, in dest local time.
        let sampleHome = anchorInstant(primaryAnchor, day: startOfDay(phases.outbound.arrivalDateTime, tz: homeTZ), homeTZ: homeTZ)
        let achievedInstant = sampleHome.addingTimeInterval(TimeInterval(peakCum))
        let achievedAnchor = TimeOfDay(minutesFromMidnight: localMinutes(achievedInstant, phases.destTZ))

        return TripScheduleSummary(
            shiftMagnitudeHours: Double(abs(chosenTarget)) / 3600.0,
            directionChosen: directionChosen,
            skippedDoseCount: skippedDoseCount,
            achievedDestinationAnchor: achievedAnchor,
            targetDestinationAnchor: primaryAnchor,
            mode: mode
        )
    }

    private static func trivialSummary(homeTZ: TimeZone, destTZ: TimeZone, mode: ShiftMode) -> TripScheduleSummary {
        TripScheduleSummary(
            shiftMagnitudeHours: 0, directionChosen: .short, skippedDoseCount: 0,
            achievedDestinationAnchor: .morning, targetDestinationAnchor: .morning, mode: mode
        )
    }

    // MARK: - Mode selection

    static func targetMode(strategy: ShiftStrategy, daysAtDestination: Int) -> ShiftMode {
        switch strategy {
        case .smart:     return daysAtDestination >= 7 ? .fullShift : .preserveAnchor
        case .gradual:   return .fullShift
        case .immediate: return .snapOnArrival
        case .none:      return .preserveAnchor
        }
    }

    // MARK: - Offset / delta math

    static func signedOffset(_ tz: TimeZone, at date: Date) -> Int { tz.secondsFromGMT(for: date) }

    /// Normalise a signed second delta to the half-open range `(-12h, +12h]`,
    /// choosing the shorter path past the international date line.
    static func normalize(_ delta: Int) -> Int {
        var d = delta
        if d > 12 * secondsPerHour { d -= secondsPerDay }
        if d <= -12 * secondsPerHour { d += secondsPerDay }
        return d
    }

    /// Backwards-compatible shortest signed delta (seconds) home → destination.
    static func shortestDelta(homeTimezone: TimeZone, destinationTimezone: TimeZone, referenceDate: Date) -> Int {
        normalize(signedOffset(destinationTimezone, at: referenceDate) - signedOffset(homeTimezone, at: referenceDate))
    }

    // MARK: - Date utilities

    static func anchorInstant(_ tod: TimeOfDay, day: Date, homeTZ: TimeZone) -> Date {
        tod.date(on: day, in: homeTZ)
    }

    static func localMinutes(_ instant: Date, _ tz: TimeZone) -> Int {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: instant)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func startOfDay(_ date: Date, tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = tz
        return cal.startOfDay(for: date)
    }

    static func isSameDay(_ a: Date, _ b: Date, tz: TimeZone) -> Bool {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = tz
        return cal.isDate(a, inSameDayAs: b)
    }

    private static func isSameDay(_ a: Date, _ b: Date) -> Bool { isSameDay(a, b, tz: TimeZone(identifier: "UTC") ?? .gmt) }

    static func addDays(_ n: Int, to date: Date, tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = tz
        return cal.date(byAdding: .day, value: n, to: startOfDay(date, tz: tz)) ?? date
    }

    static func enumerateDays(from start: Date, through end: Date, tz: TimeZone) -> [Date] {
        var days: [Date] = []
        var current = startOfDay(start, tz: tz)
        let last = startOfDay(end, tz: tz)
        guard current <= last else { return [current] }
        var guardCount = 0
        while current <= last && guardCount < 1000 {
            days.append(current)
            current = addDays(1, to: current, tz: tz)
            guardCount += 1
        }
        return days
    }
}

// MARK: - Trip phases

/// Resolves which timezone / location a given UTC instant belongs to for a trip.
struct TripPhases {
    let outbound: Flight
    let returnFlight: Flight
    let layovers: [Layover]          // already filtered to intermediate stays (≥ 8h)
    let homeTZ: TimeZone
    let destTZ: TimeZone

    private var secondsPerDay: Int { 86_400 }

    func intermediateLayover(containing instant: Date) -> Layover? {
        layovers.first { $0.contains(instant) }
    }

    /// Display timezone whose wall-clock a dose at `instant` is shown in.
    func displayTimezone(for instant: Date) -> TimeZone {
        if outbound.contains(instant) { return outbound.departureTZ }      // hold in originating (home)
        if returnFlight.contains(instant) { return returnFlight.departureTZ } // hold in originating (dest)
        if instant < outbound.departureDateTime { return homeTZ }
        if instant > returnFlight.arrivalDateTime { return homeTZ }
        if let lay = intermediateLayover(containing: instant) { return lay.timeZone }
        return destTZ
    }

    func context(for instant: Date, cum: Int, target: Int, flightDay: Bool) -> LocationContext {
        if outbound.contains(instant) { return .inFlightOutbound }
        if returnFlight.contains(instant) { return .inFlightReturn }
        if instant < outbound.departureDateTime { return cum == 0 ? .home : .preShifting }
        if instant > returnFlight.arrivalDateTime { return .postReturn }
        if intermediateLayover(containing: instant) != nil { return .layover }
        return cum == target ? .destinationStable : .destinationShifting
    }

    // MARK: Day boundaries for the simulation

    private func preShiftDays(targetSeconds: Int, rateMinutes: Int) -> Int {
        guard targetSeconds != 0, rateMinutes > 0 else { return 0 }
        let totalMin = abs(targetSeconds) / 60
        return max(0, min(7, totalMin / rateMinutes / 2))
    }

    func scheduleStartDay(preShiftEnabled: Bool, mode: ShiftMode, targetSeconds: Int, rateMinutes: Int, tz: TimeZone) -> Date {
        let departureDay = TimezoneShiftEngine.startOfDay(outbound.departureDateTime, tz: tz)
        guard mode == .fullShift, preShiftEnabled else { return departureDay }
        let pre = preShiftDays(targetSeconds: targetSeconds, rateMinutes: rateMinutes)
        return TimezoneShiftEngine.addDays(-pre, to: departureDay, tz: tz)
    }

    func scheduleEndDay(targetSeconds: Int, rateMinutes: Int, tz: TimeZone) -> Date {
        let arrivalHomeDay = TimezoneShiftEngine.startOfDay(returnFlight.arrivalDateTime, tz: tz)
        // Allow post-return ramp-down days to unwind the shift back to home.
        guard targetSeconds != 0, rateMinutes > 0 else { return arrivalHomeDay }
        let unwindDays = abs(targetSeconds) / 60 / max(1, rateMinutes) + 1
        return TimezoneShiftEngine.addDays(min(unwindDays, 60), to: arrivalHomeDay, tz: tz)
    }

    func returnRampStartDay(preShiftEnabled: Bool, targetSeconds: Int, rateMinutes: Int, tz: TimeZone) -> Date {
        let departureDay = TimezoneShiftEngine.startOfDay(returnFlight.departureDateTime, tz: tz)
        guard preShiftEnabled else {
            return TimezoneShiftEngine.startOfDay(returnFlight.arrivalDateTime, tz: tz)
        }
        let pre = preShiftDays(targetSeconds: targetSeconds, rateMinutes: rateMinutes)
        return TimezoneShiftEngine.addDays(-pre, to: departureDay, tz: tz)
    }
}
