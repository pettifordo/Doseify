import Foundation

/// Pure adherence analytics — no side effects, no stored state.
struct AdherenceCalculator {

    struct Stats {
        var totalScheduled: Int
        var totalTaken: Int
        var totalMissed: Int
        var totalSkipped: Int
        var adherencePercent: Double       // taken / (scheduled - skipped)
        var averageOnTimeScore: Double     // average score of taken doses
        var currentStreak: Int
        var longestStreak: Int
    }

    // MARK: - Core computation

    static func stats(
        for doses: [DoseEvent],
        in range: DateInterval,
        now: Date = Date()
    ) -> Stats {
        let inRange = doses.filter { range.contains($0.effectiveScheduledTime) && $0.effectiveScheduledTime <= now }

        let taken   = inRange.filter { $0.status == .taken }
        let missed  = inRange.filter { $0.status == .missed }
        let skipped = inRange.filter { $0.status == .skipped }

        let eligible = inRange.count - skipped.count
        let adherence = eligible > 0 ? Double(taken.count) / Double(eligible) * 100 : 100.0
        let avgScore  = taken.isEmpty ? 0 : taken.map(\.score).reduce(0, +) / Double(taken.count)

        let (current, longest) = streaks(from: doses, now: now)

        return Stats(
            totalScheduled: inRange.count,
            totalTaken: taken.count,
            totalMissed: missed.count,
            totalSkipped: skipped.count,
            adherencePercent: adherence,
            averageOnTimeScore: avgScore,
            currentStreak: current,
            longestStreak: longest
        )
    }

    // MARK: - Adherence windows

    static func rolling7Day(for doses: [DoseEvent], now: Date = Date()) -> Stats {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now))!
        return stats(for: doses, in: DateInterval(start: start, end: now), now: now)
    }

    static func rolling30Day(for doses: [DoseEvent], now: Date = Date()) -> Stats {
        let start = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: now))!
        return stats(for: doses, in: DateInterval(start: start, end: now), now: now)
    }

    static func rolling90Day(for doses: [DoseEvent], now: Date = Date()) -> Stats {
        let start = Calendar.current.date(byAdding: .day, value: -89, to: Calendar.current.startOfDay(for: now))!
        return stats(for: doses, in: DateInterval(start: start, end: now), now: now)
    }

    static func allTime(for doses: [DoseEvent], now: Date = Date()) -> Stats {
        guard let earliest = doses.map(\.effectiveScheduledTime).min() else {
            return Stats(totalScheduled: 0, totalTaken: 0, totalMissed: 0, totalSkipped: 0,
                         adherencePercent: 100, averageOnTimeScore: 0, currentStreak: 0, longestStreak: 0)
        }
        // DateInterval requires end >= start. If every dose is scheduled in the
        // future (e.g. fresh install with only upcoming doses), clamp to `now`
        // so we don't trap with EXC_BREAKPOINT.
        let start = min(earliest, now)
        return stats(for: doses, in: DateInterval(start: start, end: now), now: now)
    }

    // MARK: - Per-day breakdown (calendar heat-map)

    struct DayAdherence: Identifiable {
        let day: Date
        let scheduled: Int   // non-skipped doses that were due by `now`
        let taken: Int
        var id: Date { day }
        /// Fraction taken, or nil when nothing was scheduled/due that day.
        var fraction: Double? { scheduled > 0 ? Double(taken) / Double(scheduled) : nil }
    }

    /// Taken/scheduled per day for the last `days` days, oldest first. Skipped
    /// doses and not-yet-due doses are excluded.
    static func dailyBreakdown(for doses: [DoseEvent], days: Int, now: Date = Date()) -> [DayAdherence] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var result: [DayAdherence] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            let dayDoses = doses.filter {
                $0.effectiveScheduledTime >= day && $0.effectiveScheduledTime < dayEnd
                && $0.effectiveScheduledTime <= now && $0.status != .skipped
            }
            let taken = dayDoses.filter { $0.status == .taken }.count
            result.append(DayAdherence(day: day, scheduled: dayDoses.count, taken: taken))
        }
        return result
    }

    // MARK: - Streak computation

    /// Returns (currentStreak, longestStreak) in days.
    /// A streak day = all non-skipped scheduled doses have status == .taken (score > 0).
    static func streaks(from doses: [DoseEvent], now: Date = Date()) -> (current: Int, longest: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        // Group doses by calendar day
        var byDay: [Date: [DoseEvent]] = [:]
        for dose in doses where dose.effectiveScheduledTime <= now {
            let day = cal.startOfDay(for: dose.effectiveScheduledTime)
            byDay[day, default: []].append(dose)
        }

        guard !byDay.isEmpty else { return (0, 0) }

        let sortedDays = byDay.keys.sorted()

        func dayPassed(_ day: Date) -> Bool {
            let dayDoses = byDay[day] ?? []
            let eligible = dayDoses.filter { $0.status != .skipped }
            guard !eligible.isEmpty else { return true } // no doses = not a streak breaker
            return eligible.allSatisfy { $0.status == .taken }
        }

        // Current streak: walk back from today
        var current = 0
        var day = today
        while let _ = byDay[day] {
            if dayPassed(day) {
                current += 1
            } else {
                break
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }

        // Longest streak: scan all days
        var longest = 0
        var run = 0
        for d in sortedDays {
            if dayPassed(d) {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }

        return (current, longest)
    }

    // MARK: - Milestone detection

    static let milestones = [7, 30, 90, 180, 365]

    static func newlyReachedMilestone(previousStreak: Int, currentStreak: Int) -> Int? {
        milestones.first { $0 > previousStreak && $0 <= currentStreak }
    }
}
