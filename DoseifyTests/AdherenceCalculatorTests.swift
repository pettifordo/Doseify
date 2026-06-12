import Testing
import Foundation
import SwiftData
@testable import Doseify

@Suite("AdherenceCalculator")
struct AdherenceCalculatorTests {

    // MARK: - Helpers

    let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // Note: DoseEvent is a SwiftData @Model; full integration tests require a ModelContainer.
    // The pure-logic milestone/streak tests below exercise AdherenceCalculator without models.

    // MARK: - Streak tests

    @Test("No doses → 0 streak")
    func emptyStreak() {
        let (current, longest) = AdherenceCalculator.streaks(from: [], now: baseDate)
        #expect(current == 0 && longest == 0)
    }

    @Test("Milestone detection at 7 days")
    func milestoneAt7() {
        #expect(AdherenceCalculator.newlyReachedMilestone(previousStreak: 6, currentStreak: 7) == 7)
    }

    @Test("No milestone if already past it")
    func noRepeatMilestone() {
        #expect(AdherenceCalculator.newlyReachedMilestone(previousStreak: 8, currentStreak: 9) == nil)
    }

    @Test("Milestone list contains expected values")
    func milestoneList() {
        #expect(AdherenceCalculator.milestones == [7, 30, 90, 180, 365])
    }

    // MARK: - Daily breakdown (heat-map)

    @Test("dailyBreakdown counts taken vs scheduled per day, excluding skipped and future")
    func dailyBreakdownCounts() throws {
        let container = try ModelContainer(
            for: Medication.self, DoseEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = ModelContext(container)
        let med = Medication(name: "A")
        ctx.insert(med)

        let cal = Calendar.current
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: baseDate) ?? baseDate

        func add(daysAgo: Int, hour: Int = 8, status: DoseStatus) {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now)) ?? now
            let t = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
            let d = DoseEvent(medication: med, scheduledTimeHome: t, effectiveScheduledTime: t, effectiveTimezone: "UTC")
            d.status = status
            ctx.insert(d)
        }

        add(daysAgo: 1, status: .taken)      // yesterday: 1 taken
        add(daysAgo: 1, hour: 20, status: .missed)   // yesterday: + 1 missed → 1/2
        add(daysAgo: 2, status: .taken)      // 2 days ago: 1 taken
        add(daysAgo: 2, hour: 20, status: .skipped)  // skipped is excluded → 1/1
        let future = DoseEvent(medication: med,
                               scheduledTimeHome: now.addingTimeInterval(3600),
                               effectiveScheduledTime: now.addingTimeInterval(3600),
                               effectiveTimezone: "UTC")
        future.status = .pending
        ctx.insert(future)                   // later today, not yet due → excluded

        let all = try ctx.fetch(FetchDescriptor<DoseEvent>())
        let breakdown = AdherenceCalculator.dailyBreakdown(for: all, days: 5, now: now)

        #expect(breakdown.count == 5)                 // oldest-first, today last
        let yesterday = breakdown[3]
        let twoDaysAgo = breakdown[2]
        #expect(yesterday.scheduled == 2 && yesterday.taken == 1)
        #expect(abs((yesterday.fraction ?? -1) - 0.5) < 0.001)
        #expect(twoDaysAgo.scheduled == 1 && twoDaysAgo.taken == 1)   // skipped not counted
        #expect(breakdown.last?.fraction == nil)      // today: nothing due yet
    }
}

// A test-only stand-in since we can't easily create real SwiftData DoseEvents in unit tests.
// The real DoseEvent is an @Model; for pure-logic tests we'd mock the interface.
// These tests verify the calculator's logic via AdherenceCalculator.streaks().
// Full integration tests require a ModelContainer (see future test phases).
