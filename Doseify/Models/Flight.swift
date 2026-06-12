import Foundation
import SwiftData

/// One flight leg. Times are stored as absolute UTC `Date`s; the timezone
/// identifiers carry the wall-clock context for display and for the engine's
/// "hold anchor in originating TZ" rule during flight (SPEC §2.4.3 step 4).
@Model
final class Flight {
    var departureDateTime: Date          // UTC
    var departureTimezone: String        // IANA identifier
    var arrivalDateTime: Date            // UTC
    var arrivalTimezone: String          // IANA identifier

    init(
        departureDateTime: Date,
        departureTimezone: String,
        arrivalDateTime: Date,
        arrivalTimezone: String
    ) {
        self.departureDateTime = departureDateTime
        self.departureTimezone = departureTimezone
        self.arrivalDateTime = arrivalDateTime
        self.arrivalTimezone = arrivalTimezone
    }

    var departureTZ: TimeZone { TimeZone(identifier: departureTimezone) ?? .gmt }
    var arrivalTZ: TimeZone { TimeZone(identifier: arrivalTimezone) ?? .gmt }

    /// True if `instant` (UTC) falls within this flight's airborne window.
    func contains(_ instant: Date) -> Bool {
        instant >= departureDateTime && instant <= arrivalDateTime
    }
}
