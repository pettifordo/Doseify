import Foundation
import SwiftData

@Model
final class SideEffectLog {
    var id: UUID
    var timestamp: Date
    var severity: Int          // 1–10
    var bodyArea: String?
    var notes: String

    @Relationship(deleteRule: .nullify)
    var relatedDose: DoseEvent?

    init(severity: Int, notes: String = "", bodyArea: String? = nil, relatedDose: DoseEvent? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.severity = max(1, min(10, severity))
        self.notes = notes
        self.bodyArea = bodyArea
        self.relatedDose = relatedDose
    }
}
