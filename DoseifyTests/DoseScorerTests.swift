import Testing
import Foundation
@testable import Doseify

@Suite("DoseScorer")
struct DoseScorerTests {

    let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Score tests

    @Test("Taken exactly on time → 100")
    func takenOnTime() {
        let score = DoseScorer.score(scheduledTime: baseTime, loggedTime: baseTime)
        #expect(score == 100.0)
    }

    @Test("Taken 3 min early → 100")
    func takenEarly() {
        let logged = baseTime.addingTimeInterval(-3 * 60)
        let score = DoseScorer.score(scheduledTime: baseTime, loggedTime: logged)
        #expect(score == 100.0)
    }

    @Test("Taken within on-time window → 100")
    func takenWithinWindow() {
        let logged = baseTime.addingTimeInterval(4 * 60)  // 4 min, window=5
        let score = DoseScorer.score(scheduledTime: baseTime, loggedTime: logged)
        #expect(score == 100.0)
    }

    @Test("Taken at cutoff → 0")
    func takenAtCutoff() {
        let logged = baseTime.addingTimeInterval(120 * 60)
        let score = DoseScorer.score(scheduledTime: baseTime, loggedTime: logged)
        #expect(score == 0.0)
    }

    @Test("Taken at midpoint → ~50")
    func takenAtMidpoint() {
        // midpoint between window end (5 min) and cutoff (120 min) → ~50%
        let midMins = 5.0 + (120.0 - 5.0) / 2.0
        let logged = baseTime.addingTimeInterval(midMins * 60)
        let score = DoseScorer.score(scheduledTime: baseTime, loggedTime: logged)
        #expect(abs(score - 50.0) < 1.0)
    }

    @Test("Taken past cutoff → 0")
    func takenPastCutoff() {
        let logged = baseTime.addingTimeInterval(200 * 60)
        let score = DoseScorer.score(scheduledTime: baseTime, loggedTime: logged)
        #expect(score == 0.0)
    }

    @Test("Score is in 0–100 for any reasonable input")
    func scoreInRange() {
        for mins in stride(from: -10.0, through: 200.0, by: 5.0) {
            let logged = baseTime.addingTimeInterval(mins * 60)
            let score = DoseScorer.score(scheduledTime: baseTime, loggedTime: logged)
            #expect(score >= 0 && score <= 100)
        }
    }

    // MARK: - Pending status tests

    @Test("Before cutoff → pending")
    func pendingBeforeCutoff() {
        let now = baseTime.addingTimeInterval(30 * 60)  // 30 min after
        let status = DoseScorer.pendingStatus(effectiveScheduledTime: baseTime, now: now)
        #expect(status == .pending)
    }

    @Test("After cutoff → missed")
    func missedAfterCutoff() {
        let now = baseTime.addingTimeInterval(121 * 60)  // 121 min after
        let status = DoseScorer.pendingStatus(effectiveScheduledTime: baseTime, now: now)
        #expect(status == .missed)
    }

    @Test("Exactly at cutoff → missed")
    func missedAtCutoff() {
        let now = baseTime.addingTimeInterval(120 * 60)
        let status = DoseScorer.pendingStatus(effectiveScheduledTime: baseTime, now: now)
        #expect(status == .missed)
    }
}
