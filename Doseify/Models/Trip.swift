import Foundation
import SwiftData

/// A planned trip. The shift schedule is derived from the flights, layovers,
/// destination timezone, and strategy by `TimezoneShiftEngine` (SPEC §2.4).
///
/// `startDate` / `endDate` are denormalized convenience markers (departure day /
/// return day) kept in sync with the flights so SwiftData `@Query` sorts and
/// list grouping stay simple. The engine itself reads the flights, not these.
@Model
final class Trip {
    var id: UUID
    var name: String
    var destinationTimezone: String
    var shiftStrategy: ShiftStrategy
    var preShiftEnabled: Bool
    var status: TripStatus

    /// When true, any dose whose shifted time lands inside the user's sleep window
    /// fires a repeating wake-up alarm instead of a quiet reminder (default).
    var alarmForSleepWindowDoses: Bool = false

    // Denormalized for queries / list display. Kept in sync via `syncDatesFromFlights()`.
    var startDate: Date
    var endDate: Date

    @Relationship(deleteRule: .cascade) var outboundFlight: Flight?
    @Relationship(deleteRule: .cascade) var returnFlight: Flight?
    @Relationship(deleteRule: .cascade) var layovers: [Layover] = []

    init(
        name: String = "",
        destinationTimezone: String,
        shiftStrategy: ShiftStrategy = .smart,
        preShiftEnabled: Bool = true,
        alarmForSleepWindowDoses: Bool = false,
        outboundFlight: Flight,
        returnFlight: Flight,
        layovers: [Layover] = []
    ) {
        self.id = UUID()
        self.name = name
        self.destinationTimezone = destinationTimezone
        self.shiftStrategy = shiftStrategy
        self.preShiftEnabled = preShiftEnabled
        self.alarmForSleepWindowDoses = alarmForSleepWindowDoses
        self.status = .planned
        self.outboundFlight = outboundFlight
        self.returnFlight = returnFlight
        self.layovers = layovers
        // Departure day = outbound departure; return day = return arrival (back home).
        self.startDate = outboundFlight.departureDateTime
        self.endDate = returnFlight.arrivalDateTime
    }

    /// Re-derive `startDate` / `endDate` from the current flights. Call after
    /// editing a flight time so queries and list grouping stay accurate.
    func syncDatesFromFlights() {
        if let out = outboundFlight { startDate = out.departureDateTime }
        if let ret = returnFlight { endDate = ret.arrivalDateTime }
    }

    var durationDays: Int {
        let cal = Calendar(identifier: .gregorian)
        return cal.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    /// Days spent at the destination: outbound arrival → return departure (SPEC §2.4.3 step 2).
    var daysAtDestination: Int {
        guard let arrive = outboundFlight?.arrivalDateTime,
              let depart = returnFlight?.departureDateTime else { return durationDays }
        let cal = Calendar(identifier: .gregorian)
        return max(0, cal.dateComponents([.day], from: arrive, to: depart).day ?? 0)
    }
}
