import Foundation

/// A movement's estimated 1RM over the cached window, with the verdict US-9
/// asks the app to draw from it (#41).
///
/// Carries the points and the two statements about them — "enough to plot at
/// all" (AC3) and "stalled" (AC2) — in one place, so the chart, the badge and
/// the empty state cannot disagree about the same series.
struct ExerciseProgression: Equatable, Sendable {
    /// Number of recent sessions that must pass without a new best before a
    /// movement counts as plateaued (US-9 AC2).
    static let plateauSessionCount = 3
    /// Fewer usable sessions than this and there is nothing to draw a line
    /// between (US-9 AC3).
    static let minimumPlottableSessions = 2

    /// Identity of the movement across sessions — `ExerciseSummary.key`.
    let id: String
    /// The title as the most recent session spells it, matching the list.
    let title: String
    /// Oldest first, one point per session. Only sessions that carry a usable
    /// set appear: a week of bodyweight-only work leaves no point behind,
    /// because Epley has nothing to project from.
    let points: [ProgressionPoint]

    /// Whether the curve can be drawn: two points make a line, one makes a
    /// dot that suggests a trend nobody measured (AC3).
    var isPlottable: Bool { points.count >= Self.minimumPlottableSessions }

    /// Whether the last three sessions produced no new best (AC2).
    ///
    /// Read as "no new peak in three sessions", not as "three times slightly
    /// down": each of the three most recent sessions is compared against the
    /// best *before* them, so 90 → 100 → 95 → 98 → 99 counts as a plateau even
    /// though the last three sessions rose against each other. That is the
    /// honest reading of AC2 — none of them reached a higher 1RM — and it is
    /// also what a lifter means by stalling.
    ///
    /// A movement therefore needs a fourth session before it can stall: with
    /// only three, the first of them set the best and there is nothing earlier
    /// it failed to beat.
    var isPlateaued: Bool {
        guard points.count > Self.plateauSessionCount else { return false }
        let recent = points.suffix(Self.plateauSessionCount)
        let earlierBest = points
            .dropLast(Self.plateauSessionCount)
            .map(\.estimatedOneRepMaxKg)
            .max()
        guard let earlierBest else { return false }
        return recent.allSatisfy { $0.estimatedOneRepMaxKg <= earlierBest }
    }

    /// The best estimate in the window — the number the detail header leads
    /// with.
    var bestEstimateKg: Double? {
        points.map(\.estimatedOneRepMaxKg).max()
    }

    /// The most recent session's estimate.
    var latestEstimateKg: Double? {
        points.last?.estimatedOneRepMaxKg
    }
}
