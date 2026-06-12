import Foundation
import SwiftData

/// An intermediate stop on a multi-leg trip. The engine treats a layover as an
/// intermediate stay (scheduling doses in the layover's TZ) only when its
/// duration is at least 8 hours; shorter layovers are ignored (SPEC §2.4.6).
@Model
final class Layover {
    var airportCode: String
    var timezone: String                 // IANA identifier
    var arrivalDateTime: Date            // UTC
    var departureDateTime: Date          // UTC

    init(
        airportCode: String,
        timezone: String,
        arrivalDateTime: Date,
        departureDateTime: Date
    ) {
        self.airportCode = airportCode
        self.timezone = timezone
        self.arrivalDateTime = arrivalDateTime
        self.departureDateTime = departureDateTime
    }

    var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .gmt }

    var durationSeconds: TimeInterval { departureDateTime.timeIntervalSince(arrivalDateTime) }

    /// SPEC §2.4.6: only layovers ≥ 8h count as intermediate stays.
    var isIntermediateStay: Bool { durationSeconds >= 8 * 3600 }

    /// True if `instant` (UTC) falls within this layover's ground window.
    func contains(_ instant: Date) -> Bool {
        instant >= arrivalDateTime && instant <= departureDateTime
    }
}
