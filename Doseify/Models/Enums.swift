import Foundation

enum DoseStatus: String, Codable, CaseIterable {
    case pending
    case taken
    case missed
    case skipped
}

/// How a trip's dose times migrate toward the destination.
///
/// - `smart`: the engine decides — full shift for stays ≥ 7 days, otherwise
///   keep the home body-time and accept odd local times (see SPEC §2.4.3 step 2).
/// - `gradual`: always attempt a full shift, ramping at the per-drug rate.
/// - `immediate`: snap to destination time on arrival.
/// - `none`: keep home time for the whole trip.
enum ShiftStrategy: String, Codable, CaseIterable {
    case smart
    case gradual
    case immediate
    case none
}

/// Per-drug preference for which way around the 24-hour clock to shift.
///
/// - `smart`: let the engine pick whichever direction causes fewer
///   forbidden-window (sleep) breaches.
/// - `alwaysShortest`: always take the geographic shortest path, even if it
///   means more held doses.
enum ShiftDirectionPreference: String, Codable, CaseIterable {
    case smart
    case alwaysShortest
}

enum TripStatus: String, Codable, CaseIterable {
    case planned
    case active
    case completed
    case cancelled
}

enum AppTheme: String, Codable, CaseIterable {
    case light
    case dark
    case system
}
