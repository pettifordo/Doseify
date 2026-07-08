import Foundation
import Testing
@testable import DoseifyEngine

// Fixture-driven tests: each JSON file was computed by the reference
// JavaScript engine; the Swift port must reproduce it.

private struct Fixture: Decodable {
    struct Input: Decodable {
        let homeOffsetHours: Double
        let destOffsetHours: Double
        let departureUTC: Date
        let arrivalUTC: Date
        let returnDepartureUTC: Date
        let returnArrivalUTC: Date
        let morningTime: String
        let eveningTime: String
        let preShiftDays: Int
        let stepMinutes: Int
        let medName: String
    }
    struct ExpectedDose: Decodable {
        let utc: Date
        let scheduledSlotMinutes: Int
        let accumulatedShiftMinutes: Int
        let medName: String
    }
    let label: String
    let input: Input
    let expectedDoses: [ExpectedDose]
}

private func loadFixture(_ name: String) throws -> Fixture {
    let url = try #require(Bundle.module.url(
        forResource: name, withExtension: "json", subdirectory: "Fixtures"
    ))
    let decoder = JSONDecoder()
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    decoder.dateDecodingStrategy = .custom { d in
        let s = try d.singleValueContainer().decode(String.self)
        guard let date = iso.date(from: s) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: d.codingPath, debugDescription: "Bad date: \(s)"
            ))
        }
        return date
    }
    return try decoder.decode(Fixture.self, from: Data(contentsOf: url))
}

private func components(_ time: String) throws -> DateComponents {
    let parts = time.split(separator: ":").compactMap { Int($0) }
    try #require(parts.count == 2)
    return DateComponents(hour: parts[0], minute: parts[1])
}

private func scheduleInput(_ f: Fixture) throws -> ScheduleInput {
    ScheduleInput(
        homeOffsetHours: f.input.homeOffsetHours,
        destOffsetHours: f.input.destOffsetHours,
        departureUTC: f.input.departureUTC,
        arrivalUTC: f.input.arrivalUTC,
        returnDepartureUTC: f.input.returnDepartureUTC,
        returnArrivalUTC: f.input.returnArrivalUTC,
        morningTime: try components(f.input.morningTime),
        eveningTime: try components(f.input.eveningTime),
        preShiftDays: f.input.preShiftDays,
        stepMinutes: f.input.stepMinutes,
        medName: f.input.medName
    )
}

@Suite("DoseShiftEngine fixture parity")
struct DoseShiftEngineTests {

    @Test("matches reference engine output", arguments: ["tokyo", "la", "sydney"])
    func matchesFixture(name: String) throws {
        let fixture = try loadFixture(name)
        let doses = try DoseShiftEngine.generateDoses(input: try scheduleInput(fixture))

        // 1. Same count of doses.
        #expect(doses.count == fixture.expectedDoses.count,
                "\(fixture.label): expected \(fixture.expectedDoses.count) doses, got \(doses.count)")

        // 2. Every consecutive gap between 11.5h and 12.5h inclusive.
        for (a, b) in zip(doses, doses.dropFirst()) {
            let gapHours = b.utc.timeIntervalSince(a.utc) / 3600
            #expect(gapHours >= 11.5 && gapHours <= 12.5,
                    "\(fixture.label): gap of \(gapHours)h between \(a.utc) and \(b.utc)")
        }

        // 3. Each dose matches: utc within 1s, integer fields exactly.
        for (got, want) in zip(doses, fixture.expectedDoses) {
            #expect(abs(got.utc.timeIntervalSince(want.utc)) <= 1,
                    "\(fixture.label): utc \(got.utc) vs expected \(want.utc)")
            #expect(got.scheduledSlotMinutes == want.scheduledSlotMinutes,
                    "\(fixture.label): slot at \(want.utc)")
            #expect(got.accumulatedShiftMinutes == want.accumulatedShiftMinutes,
                    "\(fixture.label): shift at \(want.utc)")
            #expect(got.medName == want.medName)
        }
    }

    @Test("rejects meds without two daily times")
    func rejectsWrongFrequency() throws {
        let fixture = try loadFixture("tokyo")
        var input = try scheduleInput(fixture)
        input = ScheduleInput(
            homeOffsetHours: input.homeOffsetHours,
            destOffsetHours: input.destOffsetHours,
            departureUTC: input.departureUTC,
            arrivalUTC: input.arrivalUTC,
            returnDepartureUTC: input.returnDepartureUTC,
            returnArrivalUTC: input.returnArrivalUTC,
            morningTime: DateComponents(),   // no hour → not a valid daily time
            eveningTime: input.eveningTime,
            preShiftDays: input.preShiftDays,
            stepMinutes: input.stepMinutes,
            medName: input.medName
        )
        #expect(throws: DoseShiftEngineError.unsupportedFrequency(expected: 2, got: 1)) {
            _ = try DoseShiftEngine.generateDoses(input: input)
        }
    }
}
