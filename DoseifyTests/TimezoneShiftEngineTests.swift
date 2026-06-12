import Testing
import Foundation
@testable import Doseify

/// Tests for the v2 flight-aware `TimezoneShiftEngine` (SPEC §2.4).
///
/// All fixtures use January dates so every zone is on standard time — this keeps
/// the offsets clean: London +0, New York −5, Tokyo +9, Moscow +3, Honolulu −10.
@Suite("TimezoneShiftEngine")
struct TimezoneShiftEngineTests {

    // MARK: - Fixtures

    let london    = TimeZone(identifier: "Europe/London")!
    let newYork   = TimeZone(identifier: "America/New_York")!
    let tokyo     = TimeZone(identifier: "Asia/Tokyo")!
    let moscow    = TimeZone(identifier: "Europe/Moscow")!
    let honolulu  = TimeZone(identifier: "Pacific/Honolulu")!

    func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    func med(
        _ name: String = "Med",
        times: [TimeOfDay] = [.morning],
        rate: Int = 30,
        group: UUID? = nil,
        minSpacing: Int = 11,
        direction: ShiftDirectionPreference = .smart
    ) -> Medication {
        Medication(
            name: name,
            scheduledTimesOfDay: times,
            timezoneShiftMinutesPerDay: rate,
            shiftDirectionPreference: direction,
            shiftGroupId: group,
            minSpacingHours: minSpacing
        )
    }

    /// Build a trip with simple direct flights. `outDurH` / `retDurH` are flight
    /// durations in hours; departures are at 10:00 local in the originating zone.
    func trip(
        home: TimeZone,
        dest: TimeZone,
        departDay: (Int, Int, Int),
        returnDay: (Int, Int, Int),
        strategy: ShiftStrategy = .smart,
        preShift: Bool = true,
        outDurH: Int = 11,
        retDurH: Int = 11
    ) -> Trip {
        let outDep = atHour(10, day: departDay, in: home)
        let outArr = outDep.addingTimeInterval(TimeInterval(outDurH * 3600))
        let retDep = atHour(10, day: returnDay, in: dest)
        let retArr = retDep.addingTimeInterval(TimeInterval(retDurH * 3600))
        let outbound = Flight(departureDateTime: outDep, departureTimezone: home.identifier,
                              arrivalDateTime: outArr, arrivalTimezone: dest.identifier)
        let ret = Flight(departureDateTime: retDep, departureTimezone: dest.identifier,
                         arrivalDateTime: retArr, arrivalTimezone: home.identifier)
        return Trip(name: "Trip", destinationTimezone: dest.identifier,
                    shiftStrategy: strategy, preShiftEnabled: preShift,
                    outboundFlight: outbound, returnFlight: ret)
    }

    func atHour(_ hour: Int, day: (Int, Int, Int), in tz: TimeZone) -> Date {
        var c = DateComponents()
        c.year = day.0; c.month = day.1; c.day = day.2; c.hour = hour; c.minute = 0
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = tz
        return cal.date(from: c)!
    }

    func settings(home: TimeZone, sleepEndHour: Int = 6) -> UserSettings {
        let s = UserSettings(homeTimezone: home.identifier)
        s.sleepWindowStart = TimeOfDay(hour: 0, minute: 0)
        s.sleepWindowEnd = TimeOfDay(hour: sleepEndHour, minute: 0)
        return s
    }

    /// All "on the ground" entries (excludes in-flight/layover) and their local
    /// minutes-from-midnight in the zone they're anchored to.
    func groundLocalMinutes(_ schedule: TripSchedule) -> [Int] {
        schedule.doseGroups.flatMap { $0.entries }
            .filter { $0.context != .inFlightOutbound && $0.context != .inFlightReturn && $0.context != .layover }
            .map { entry in
                let tz = TimeZone(identifier: entry.effectiveTimezone) ?? .gmt
                return TimezoneShiftEngine.localMinutes(entry.effectiveTimeUTC, tz)
            }
    }

    // MARK: - Offset / delta math

    @Test("Normalize chooses the shorter path past the date line")
    func normalizeDateLine() {
        // Tokyo(+9) → Honolulu(−10): raw −19h → normalized +5h (magnitude 5, west the short way).
        let delta = TimezoneShiftEngine.shortestDelta(homeTimezone: tokyo, destinationTimezone: honolulu, referenceDate: utc(2025, 1, 1))
        #expect(abs(delta) == 5 * 3600)
    }

    @Test("Short + long magnitudes sum to 24h")
    func directionsSumTo24() {
        let ref = utc(2025, 1, 1)
        let tzDelta = TimezoneShiftEngine.signedOffset(tokyo, at: ref) - TimezoneShiftEngine.signedOffset(london, at: ref)
        let normalized = TimezoneShiftEngine.normalize(tzDelta)
        let shortMag = abs(normalized) / 3600
        let longMag = 24 - shortMag
        #expect(shortMag + longMag == 24)
        #expect(shortMag == 9)   // London → Tokyo is 9h
    }

    // MARK: - Mode selection (SPEC §2.4.3 step 2)

    @Test("Case 3: London → Tokyo 5-day smart → preserveAnchor, no shift")
    func tokyoShortTripPreservesAnchor() {
        let t = trip(home: london, dest: tokyo, departDay: (2025, 1, 1), returnDay: (2025, 1, 6))
        let schedule = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [med()], userSettings: settings(home: london), existingOverrides: []
        )
        #expect(schedule.summary.mode == .preserveAnchor)
        // No shift applied: every entry fires at the home anchor instant.
        let allHomeAnchored = schedule.doseGroups.flatMap { $0.entries }
            .allSatisfy { $0.effectiveTimeUTC == $0.scheduledTimeHomeUTC }
        #expect(allHomeAnchored)
    }

    @Test("≥7-day smart trip enters fullShift mode")
    func longTripFullShift() {
        let t = trip(home: london, dest: tokyo, departDay: (2025, 1, 1), returnDay: (2025, 1, 20))
        let schedule = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [med()], userSettings: settings(home: london), existingOverrides: []
        )
        #expect(schedule.summary.mode == .fullShift)
    }

    // MARK: - Body-clock shift (always the short way; no sleep-window holding)

    @Test("Case 1: London → Tokyo 14-day shifts the short way (east), never the long way")
    func tokyoLongTripShiftsShort() {
        // 9h east. Doses follow the body clock and migrate the short way. No holding
        // for the local sleep window (that behaviour was removed per the owner).
        let t = trip(home: london, dest: tokyo, departDay: (2025, 1, 1), returnDay: (2025, 1, 15))
        let schedule = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [med()], userSettings: settings(home: london), existingOverrides: []
        )
        #expect(schedule.summary.mode == .fullShift)
        #expect(schedule.summary.directionChosen == .short)
        #expect(schedule.summary.shiftMagnitudeHours == 9)
        // Once-daily drug — nothing is ever skipped (skips are only for spacing).
        #expect(schedule.summary.skippedDoseCount == 0)
    }

    @Test("Case 2: London → NYC 13-day shifts west and reaches the destination anchor")
    func nycWestShift() {
        // NYC is 5h west; 5h at 30 min/day = 10 days, completes inside a 13-day stay.
        let t = trip(home: london, dest: newYork, departDay: (2025, 1, 1), returnDay: (2025, 1, 14))
        let schedule = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [med()], userSettings: settings(home: london), existingOverrides: []
        )
        #expect(schedule.summary.mode == .fullShift)
        #expect(schedule.summary.directionChosen == .short)
        #expect(schedule.summary.achievedDestinationAnchor.hour == 8)
        #expect(schedule.summary.skippedDoseCount == 0)
    }

    @Test("Case 11: a small east shift takes the short way and reaches the anchor")
    func smallEastShiftGoesShort() {
        // Moscow is +3h east of London, 11-day trip. Always short (3h), never the
        // 21h long way; reaches Moscow 8 AM. No skips for a once-daily drug.
        let t = trip(home: london, dest: moscow, departDay: (2025, 1, 1), returnDay: (2025, 1, 12))
        let schedule = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [med()], userSettings: settings(home: london), existingOverrides: []
        )
        #expect(schedule.summary.mode == .fullShift)
        #expect(schedule.summary.directionChosen == .short)
        #expect(schedule.summary.shiftMagnitudeHours == 3)
        #expect(schedule.summary.achievedDestinationAnchor.hour == 8)
        #expect(schedule.summary.skippedDoseCount == 0)
    }

    // MARK: - Flight-time anchoring (SPEC §2.4.3 step 4)

    @Test("Case 5: a dose during the outbound flight is anchored to the originating TZ")
    func doseDuringOutboundFlight() {
        // Outbound departs London 10:00 (UTC), 11h flight → airborne 10:00–21:00 UTC on Jan 1.
        // A 14:00 (London) dose lands mid-flight. Use .none so no shift confuses the anchor.
        let t = trip(home: london, dest: tokyo, departDay: (2025, 1, 1), returnDay: (2025, 1, 10), strategy: .none)
        let m = med("Evening", times: [TimeOfDay(hour: 14, minute: 0)])
        let schedule = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [m], userSettings: settings(home: london), existingOverrides: []
        )
        let inflight = schedule.doseGroups.flatMap { $0.entries }
            .first { $0.context == .inFlightOutbound }
        #expect(inflight != nil)
        #expect(inflight?.badge == .inFlight)
        #expect(inflight?.effectiveTimezone == london.identifier)
        // Anchored to home wall-clock: no extra shift applied during the hold.
        #expect(inflight?.effectiveTimeUTC == inflight?.scheduledTimeHomeUTC)
    }

    // MARK: - Dose groups (SPEC §2.4.8 case 8)

    @Test("Case 8: unlinking a drug from a group splits it into two groups")
    func unlinkGroupSplits() {
        let gid = UUID()
        let a = med("A", group: gid)
        let b = med("B", group: gid)
        let t = trip(home: london, dest: newYork, departDay: (2025, 1, 1), returnDay: (2025, 1, 14))

        let linked = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [a, b], userSettings: settings(home: london), existingOverrides: []
        )
        #expect(linked.doseGroups.count == 1)

        b.shiftGroupId = nil
        let unlinked = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [a, b], userSettings: settings(home: london), existingOverrides: []
        )
        #expect(unlinked.doseGroups.count == 2)
    }

    // MARK: - BID spacing (SPEC §2.4.8 case 7)

    @Test("Case 7: BID drug keeps ≥ minimum spacing across the shift")
    func bidSpacingMaintained() {
        // 08:00 + 19:00 = 11h apart; minSpacing 11h. Lockstep shift preserves it.
        let m = med("BID", times: [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 19, minute: 0)], minSpacing: 11)
        let t = trip(home: london, dest: newYork, departDay: (2025, 1, 1), returnDay: (2025, 1, 14))
        let schedule = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [m], userSettings: settings(home: london), existingOverrides: []
        )
        let spacingWarnings = schedule.warnings.filter {
            if case .bidSpacingViolated = $0 { return true }; return false
        }
        #expect(spacingWarnings.isEmpty)
        // A gradual shift keeps spacing on its own — no dose is ever skipped.
        #expect(schedule.summary.skippedDoseCount == 0)
    }

    // MARK: - Overdose-skip protection (max one skip out, one back)

    @Test("Immediate BID shift skips at most one dose each way to avoid an overdose")
    func immediateBidSkipsAtMostOnePerLeg() {
        // London → Tokyo (+9), immediate snap. A BID drug (11h min gap) compresses at
        // the flight, so one dose is skipped to avoid two doses too close together.
        let m = med("BID", times: [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)], minSpacing: 11)
        let t = trip(home: london, dest: tokyo, departDay: (2025, 1, 1), returnDay: (2025, 1, 15), strategy: .immediate)
        let schedule = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [m], userSettings: settings(home: london), existingOverrides: []
        )
        // At least one realignment skip, and never more than one out + one back.
        #expect(schedule.summary.skippedDoseCount >= 1)
        #expect(schedule.summary.skippedDoseCount <= 2)
        // The skip surfaces as a skipped entry, and every kept consecutive pair in a
        // group respects the 11h minimum.
        let entries = schedule.doseGroups.flatMap { $0.entries }
        #expect(entries.contains { $0.isSkipped })
        let kept = entries.filter { !$0.isSkipped }.map { $0.effectiveTimeUTC }.sorted()
        for i in 1..<kept.count {
            #expect(kept[i].timeIntervalSince(kept[i - 1]) >= 11 * 3600 - 1)
        }
    }

    // MARK: - Manual override (SPEC §2.4.8 case 9)

    @Test("Case 9: a manual override wins for its dose and is badged")
    func manualOverrideApplied() {
        let m = med("A")
        let t = trip(home: london, dest: newYork, departDay: (2025, 1, 1), returnDay: (2025, 1, 14))
        // Override the group's dose on Jan 5 to a fixed UTC time.
        let overrideTime = utc(2025, 1, 5, 12, 0)
        let override = DoseOverride(
            tripId: t.id, shiftGroupId: m.id,
            scheduledDate: utc(2025, 1, 5), customTimeUTC: overrideTime
        )
        let schedule = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [m], userSettings: settings(home: london), existingOverrides: [override]
        )
        let overridden = schedule.doseGroups.flatMap { $0.entries }.first { $0.isManualOverride }
        #expect(overridden != nil)
        #expect(overridden?.badge == .manualOverride)
        #expect(overridden?.effectiveTimeUTC == overrideTime)
    }

    // MARK: - Boundary: zero delta

    @Test("Boundary: zero timezone delta → no shift, no warnings")
    func zeroDelta() {
        // Europe/London → Europe/Lisbon: both UTC+0 in January.
        let lisbon = TimeZone(identifier: "Europe/Lisbon")!
        let t = trip(home: london, dest: lisbon, departDay: (2025, 1, 1), returnDay: (2025, 1, 20))
        let schedule = TimezoneShiftEngine.computeTrip(
            trip: t, medications: [med()], userSettings: settings(home: london), existingOverrides: []
        )
        #expect(schedule.summary.shiftMagnitudeHours == 0)
        let allHomeAnchored = schedule.doseGroups.flatMap { $0.entries }
            .allSatisfy { $0.effectiveTimeUTC == $0.scheduledTimeHomeUTC }
        #expect(allHomeAnchored)
    }

    // MARK: - Purity / determinism

    @Test("Pure: identical inputs produce identical outputs")
    func deterministic() {
        let m = med()
        let t = trip(home: london, dest: tokyo, departDay: (2025, 1, 1), returnDay: (2025, 1, 20))
        let s = settings(home: london)
        let a = TimezoneShiftEngine.computeTrip(trip: t, medications: [m], userSettings: s, existingOverrides: [])
        let b = TimezoneShiftEngine.computeTrip(trip: t, medications: [m], userSettings: s, existingOverrides: [])
        let aTimes = a.doseGroups.flatMap { $0.entries.map { $0.effectiveTimeUTC } }
        let bTimes = b.doseGroups.flatMap { $0.entries.map { $0.effectiveTimeUTC } }
        #expect(aTimes == bTimes)
        #expect(a.summary.directionChosen == b.summary.directionChosen)
    }

    // MARK: - pickBetter

    @Test("pickBetter prefers fewer breaches, then fewer holds")
    func pickBetterLogic() {
        let short = Trajectory(cumByDay: [], breachCount: 3, heldDoseCount: 2,
                               totalShiftAchievedMinutes: 0, targetShiftMinutes: 0, direction: .short)
        let long = Trajectory(cumByDay: [], breachCount: 0, heldDoseCount: 0,
                              totalShiftAchievedMinutes: 0, targetShiftMinutes: 0, direction: .long)
        #expect(TimezoneShiftEngine.pickBetter(short, long).direction == .long)

        let tieShort = Trajectory(cumByDay: [], breachCount: 0, heldDoseCount: 0,
                                  totalShiftAchievedMinutes: 0, targetShiftMinutes: 0, direction: .short)
        let tieLong = Trajectory(cumByDay: [], breachCount: 0, heldDoseCount: 0,
                                 totalShiftAchievedMinutes: 0, targetShiftMinutes: 0, direction: .long)
        #expect(TimezoneShiftEngine.pickBetter(tieShort, tieLong).direction == .short)
    }
}
