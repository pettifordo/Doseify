import Foundation
import SwiftData

/// A user's manual edit of a single computed dose time in the trip preview.
///
/// SPEC §2.4.3 step 7: an override takes precedence over engine output for that
/// one dose only, survives subsequent engine recomputes (e.g. an edited flight
/// time), and is removable. Keyed by `(shiftGroupId, scheduledDate, slotMinutes)`.
@Model
final class DoseOverride {
    var id: UUID
    var tripId: UUID
    var shiftGroupId: UUID
    var scheduledDate: Date              // the calendar day the override applies to (UTC day marker)
    /// Which dose slot of the day this override targets, as the med's home
    /// minutes-from-midnight (e.g. 480 for 08:00). -1 = legacy row created
    /// before slots existed; matches any slot that day.
    var slotMinutes: Int = -1
    var customTimeUTC: Date              // the override time, absolute UTC
    var createdAt: Date

    init(
        tripId: UUID,
        shiftGroupId: UUID,
        scheduledDate: Date,
        slotMinutes: Int = -1,
        customTimeUTC: Date
    ) {
        self.id = UUID()
        self.tripId = tripId
        self.shiftGroupId = shiftGroupId
        self.scheduledDate = scheduledDate
        self.slotMinutes = slotMinutes
        self.customTimeUTC = customTimeUTC
        self.createdAt = Date()
    }
}
