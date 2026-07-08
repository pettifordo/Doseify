import Foundation

// Doseify V2 time-shift engine — direct port of `reference-engine.js`.
//
// Plans when to take a twice-daily medication (same dose each time) during a
// trip between two timezones, keeping every gap between consecutive doses
// within roughly 11.5–12.5 hours.
//
// Restrictions (deliberate, matching the reference):
//   - Only 2x-daily meds are supported.
//   - Timezone offsets are FIXED (hours). No IANA zones, no DST. If a trip
//     crosses a DST boundary, results will be off by an hour.
//
// The engine is pure: no I/O, no clock reads, no globals.

// MARK: - Input / output types

public struct ScheduleInput {
    public let homeOffsetHours: Double
    public let destOffsetHours: Double
    public let departureUTC: Date
    public let arrivalUTC: Date
    public let returnDepartureUTC: Date
    public let returnArrivalUTC: Date
    public let morningTime: DateComponents   // (hour, minute) in home local
    public let eveningTime: DateComponents
    public let preShiftDays: Int             // e.g. 5
    public let stepMinutes: Int              // e.g. 30
    public let medName: String

    public init(
        homeOffsetHours: Double,
        destOffsetHours: Double,
        departureUTC: Date,
        arrivalUTC: Date,
        returnDepartureUTC: Date,
        returnArrivalUTC: Date,
        morningTime: DateComponents,
        eveningTime: DateComponents,
        preShiftDays: Int,
        stepMinutes: Int,
        medName: String
    ) {
        self.homeOffsetHours = homeOffsetHours
        self.destOffsetHours = destOffsetHours
        self.departureUTC = departureUTC
        self.arrivalUTC = arrivalUTC
        self.returnDepartureUTC = returnDepartureUTC
        self.returnArrivalUTC = returnArrivalUTC
        self.morningTime = morningTime
        self.eveningTime = eveningTime
        self.preShiftDays = preShiftDays
        self.stepMinutes = stepMinutes
        self.medName = medName
    }
}

public struct DoseEvent: Equatable {
    public let medName: String
    public let utc: Date
    public let scheduledSlotMinutes: Int     // 480 for morning, 1200 for evening
    public let accumulatedShiftMinutes: Int  // rounded to int

    public init(medName: String, utc: Date, scheduledSlotMinutes: Int, accumulatedShiftMinutes: Int) {
        self.medName = medName
        self.utc = utc
        self.scheduledSlotMinutes = scheduledSlotMinutes
        self.accumulatedShiftMinutes = accumulatedShiftMinutes
    }
}

public enum DoseShiftEngineError: Error, Equatable {
    case unsupportedFrequency(expected: Int, got: Int)
}

// MARK: - Engine

public enum DoseShiftEngine {

    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86400
    private static let minute: TimeInterval = 60

    /// Generate the trip's dose schedule. Throws if the med is not 2x/day.
    public static func generateDoses(input: ScheduleInput) throws -> [DoseEvent] {
        // The reference engine takes a list of home times and rejects anything
        // that isn't exactly two. The Swift input carries two DateComponents;
        // either missing an hour means we don't have two valid daily times.
        guard let morningRaw = minutes(of: input.morningTime),
              let eveningRaw = minutes(of: input.eveningTime) else {
            throw DoseShiftEngineError.unsupportedFrequency(
                expected: 2,
                got: [minutes(of: input.morningTime), minutes(of: input.eveningTime)]
                    .compactMap { $0 }.count
            )
        }

        let morningMin = min(morningRaw, eveningRaw)
        let eveningMin = max(morningRaw, eveningRaw)
        let gapHr = Double(eveningMin - morningMin) / 60

        let homeOffset = input.homeOffsetHours
        let destOffset = input.destOffsetHours
        let shiftHr = destOffset - homeOffset
        let absShift = abs(shiftHr)
        let stepHr = Double(max(1, input.stepMinutes)) / 60

        // Pick direction and target shift.
        //   |shift| ≤ gap/2 → DIRECT: advance east, delay west; target = |shift|.
        //   |shift| > gap/2 → SWAP: delay east, advance west;
        //                     target = 24 − gap − |shift| (short way around).
        var direction: Double = 0
        var targetShiftHr: Double = 0
        if absShift > 0 {
            if absShift <= gapHr / 2 {
                direction = -sign(shiftHr)
                targetShiftHr = absShift
            } else {
                direction = sign(shiftHr)
                targetShiftHr = max(0, 24 - gapHr - absShift)
            }
        }

        let depUtc = input.departureUTC.timeIntervalSince1970
        let retArrUtc = input.returnArrivalUTC.timeIntervalSince1970

        // Emission window. The reference harness clips to a range around the
        // trip; derived from its fixtures: doses start (preShiftDays + 1) days
        // before departure and end 4 days after return-landing (exclusive).
        let rangeStart = depUtc - Double(input.preShiftDays + 1) * day
        let rangeEnd = retArrUtc + 4 * day

        let depMidHomeUtc = startOfDayInFrame(depUtc, offsetHours: homeOffset)
        let retArrMidHomeUtc = startOfDayInFrame(retArrUtc, offsetHours: homeOffset)
        let retDayInHome = Int((retArrMidHomeUtc - depMidHomeUtc) / day + 0.5)

        let daysBefore = max(input.preShiftDays + 2, 7)
        let daysAfter = max(7, Int(ceil((rangeEnd - retArrMidHomeUtc) / day)) + 2)

        var doses: [DoseEvent] = []

        func emit(_ utc: TimeInterval, scheduledSlot: Int, accShiftMin: Double) {
            guard utc >= rangeStart && utc < rangeEnd else { return }
            doses.append(DoseEvent(
                medName: input.medName,
                utc: Date(timeIntervalSince1970: utc),
                scheduledSlotMinutes: scheduledSlot,
                accumulatedShiftMinutes: Int(accShiftMin.rounded())
            ))
        }

        for d in -daysBefore...(retDayInHome + daysAfter) {
            let dayMidUtc = depMidHomeUtc + Double(d) * day

            // Symmetric triangle ramp capped at target: rises at stepHr/day
            // from the pre-shift start, falls at stepHr/day into the return.
            let stepsFromPreStart = Double(max(0, input.preShiftDays + d))
            let limitedByPreShift = min(targetShiftHr, stepsFromPreStart * stepHr)
            let stepsToReturn = Double(max(0, retDayInHome - d))
            let limitedByUnshift = min(targetShiftHr, stepsToReturn * stepHr)
            let accumShiftHr = min(limitedByPreShift, limitedByUnshift)

            let morningClockMin = Double(morningMin) + accumShiftHr * 60 * direction
            let eveningClockMin = Double(eveningMin) + accumShiftHr * 60 * direction

            emit(dayMidUtc + morningClockMin * minute, scheduledSlot: morningMin, accShiftMin: accumShiftHr * 60)
            emit(dayMidUtc + eveningClockMin * minute, scheduledSlot: eveningMin, accShiftMin: accumShiftHr * 60)
        }

        doses.sort { $0.utc < $1.utc }

        // Light safety dedupe: drop pairs within 5 minutes. Shouldn't fire
        // with this algorithm but kept as a guard against numeric edge cases.
        var out: [DoseEvent] = []
        for dose in doses {
            if let last = out.last, abs(dose.utc.timeIntervalSince(last.utc)) < 5 * minute { continue }
            out.append(dose)
        }
        return out
    }

    // MARK: Helpers

    /// UTC seconds of midnight of the calendar day in the given fixed-offset frame.
    public static func startOfDayInFrame(_ utc: TimeInterval, offsetHours: Double) -> TimeInterval {
        let localSecs = utc + offsetHours * hour
        let dayStartLocal = floor(localSecs / day) * day
        return dayStartLocal - offsetHours * hour
    }

    /// DateComponents (hour, minute) → minutes past midnight, nil if hour missing.
    private static func minutes(of comps: DateComponents) -> Int? {
        guard let h = comps.hour else { return nil }
        return h * 60 + (comps.minute ?? 0)
    }

    private static func sign(_ x: Double) -> Double {
        x > 0 ? 1 : (x < 0 ? -1 : 0)
    }
}
