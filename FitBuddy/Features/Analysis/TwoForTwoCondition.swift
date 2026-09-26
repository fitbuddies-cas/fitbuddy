import Foundation

/// Whether an exercise has earned a load increase (ADR-013, decision 5): the
/// rep target beaten by at least `requiredMargin` reps on the last working
/// set of each of the `requiredSessions` most recent sessions.
///
/// The target is the routine's, snapshotted onto the set at sync time
/// (`SetDetail.targetReps`, #240). Without one the rule is **not checkable**
/// — a state of its own, never read as met: a freely logged workout would
/// otherwise pass the condition it could not be tested against, and that is
/// the common case.
///
/// Evaluated in one place for the prompt (#232) and the report validation
/// (#233), so the model is told exactly what the app later checks.
enum TwoForTwoCondition: Equatable, Sendable {
    /// Beaten by the margin in both sessions: a load increase is on.
    case met
    /// Not beaten in at least one of them — or fewer sessions than the rule
    /// needs: the exercise progresses reps, not weight.
    case notMet
    /// A session in the pair carries no target on its last working set, so
    /// the rule has nothing to compare against.
    case notCheckable

    /// Consecutive sessions of the exercise the rule looks at.
    static let requiredSessions = 2
    /// Reps over the target each of them has to reach. The strict form of
    /// the rule (NSCA's "2-for-2"); the ACSM position stand says one to two,
    /// and ADR-013 sets the margin at two on purpose: one extra rep is form
    /// on the day, two in a row are a reserve.
    static let requiredMargin = 2

    /// The verdict over `sessions`, oldest first, as `ExerciseProgression`
    /// holds them.
    ///
    /// Only sessions that logged a working set count towards the pair: one
    /// holding warm-ups alone is not an attempt at the target.
    ///
    /// The targets are checked **before** the count: a single session
    /// without a target is `.notCheckable`, not `.notMet` — the prompt line
    /// for `.notMet` names the rep target, and there is none to name. Only
    /// with every attempt carrying a target does fewer than two of them read
    /// as `.notMet` (ADR-013, decision 5): the data is there, it just does
    /// not yet show two consecutive successes. No working set at all is
    /// `.notCheckable` for the same reason — nothing was attempted.
    static func evaluate(sessions: [ExerciseHistoryEntry]) -> TwoForTwoCondition {
        let attempts = sessions.compactMap(lastWorkingSet(in:)).suffix(requiredSessions)
        guard !attempts.isEmpty, attempts.allSatisfy({ $0.targetReps != nil }) else { return .notCheckable }
        guard attempts.count == requiredSessions else { return .notMet }
        var beaten = true
        for attempt in attempts {
            guard let target = attempt.targetReps, let reps = attempt.reps else { return .notCheckable }
            if reps - target < requiredMargin { beaten = false }
        }
        return beaten ? .met : .notMet
    }

    /// The target the most recent attempt was made against — what the prompt
    /// names for the exercise — or `nil` when it carried none.
    static func latestTarget(in sessions: [ExerciseHistoryEntry]) -> Int? {
        sessions.compactMap(lastWorkingSet(in:)).last?.targetReps
    }

    /// The last set in logged order that carries a working weight — the set
    /// the source's 2-for-2 rule reads, as `WorkingSet` defines "working".
    private static func lastWorkingSet(in session: ExerciseHistoryEntry) -> SetDetail? {
        session.sets.last { WorkingSet(set: $0) != nil }
    }
}
