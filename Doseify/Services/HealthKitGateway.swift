import Foundation
import HealthKit

/// Read-only bridge to Apple Health's **Medications** feature.
///
/// Apple (iOS 26+) exposes the user's tracked medications for **reading only**
/// (`HKUserAnnotatedMedication`). There is **no** public API to write medications
/// or dose-taken events back into Health — `HKMedicationDoseEvent` has its `init`
/// and `new` marked `NS_UNAVAILABLE` with no builder — so Doseify can *import* the
/// medication list but cannot push "taken" status into the Health timeline.
///
/// (An earlier version faked a write by saving `.mindfulSession` samples, which
/// silently polluted Mindful Minutes. That has been removed — CLAUDE.md hard rule 8.)
final class HealthKitGateway {

    static let shared = HealthKitGateway()
    private let store = HKHealthStore()

    /// A medication discovered in Apple Health, ready to import into Doseify.
    struct ImportedMedication: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let hasSchedule: Bool
    }

    /// Importing requires iOS 26+ (the Medications read API) and HealthKit support.
    var isMedicationImportSupported: Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// Ask for read access to the user's medications. Returns `false` when the
    /// feature is unsupported or the request fails. (HealthKit never reveals
    /// whether read access was actually granted — run the query and check.)
    func requestMedicationReadAuthorization() async -> Bool {
        guard isMedicationImportSupported else { return false }
        if #available(iOS 26.0, *) {
            do {
                try await store.requestAuthorization(
                    toShare: [],
                    read: [HKObjectType.userAnnotatedMedicationType()]
                )
                return true
            } catch {
                return false
            }
        }
        return false
    }

    /// Read the user's active (non-archived) medications from Apple Health.
    /// Returns an empty array when unsupported, unauthorized, or none are tracked.
    func fetchHealthMedications() async -> [ImportedMedication] {
        guard isMedicationImportSupported else { return [] }
        if #available(iOS 26.0, *) {
            let descriptor = HKUserAnnotatedMedicationQueryDescriptor(predicate: nil, limit: nil)
            do {
                let results = try await descriptor.result(for: store)
                return results
                    .filter { !$0.isArchived }
                    .map { entry in
                        let nickname = entry.nickname.flatMap { $0.isEmpty ? nil : $0 }
                        return ImportedMedication(
                            name: nickname ?? entry.medication.displayText,
                            hasSchedule: entry.hasSchedule
                        )
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            } catch {
                return []
            }
        }
        return []
    }
}
