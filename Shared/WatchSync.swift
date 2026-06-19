import Foundation

/// One dose as shown on the Watch — a small DTO that crosses WatchConnectivity.
/// Deliberately dependency-free (Foundation only) so it compiles into both the
/// iOS and watchOS targets.
struct WatchDose: Codable, Identifiable, Hashable {
    let id: UUID                // DoseEvent.id — the phone uses this to log it
    let medName: String
    let scheduledTime: Date     // effective (trip-shifted) scheduled time
    let colorHex: String
}

/// Keys + (de)coding for the phone↔watch payloads.
enum WatchSync {
    // applicationContext (latest-state) key
    static let dosesKey = "todayDoses"
    // message / userInfo keys
    static let actionKey = "action"
    static let logAction = "logDose"
    static let doseIDKey = "doseID"
    static let timeKey = "time"

    static func encodeDoses(_ doses: [WatchDose]) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(doses) else { return [dosesKey: Data()] }
        return [dosesKey: data]
    }

    static func decodeDoses(_ context: [String: Any]) -> [WatchDose]? {
        guard let data = context[dosesKey] as? Data else { return nil }
        return try? JSONDecoder().decode([WatchDose].self, from: data)
    }

    static func logMessage(doseID: UUID, time: Date) -> [String: Any] {
        [actionKey: logAction, doseIDKey: doseID.uuidString, timeKey: time.timeIntervalSince1970]
    }

    static func parseLog(_ payload: [String: Any]) -> (id: UUID, time: Date)? {
        guard payload[actionKey] as? String == logAction,
              let idString = payload[doseIDKey] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        let time = (payload[timeKey] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
        return (id, time)
    }
}
