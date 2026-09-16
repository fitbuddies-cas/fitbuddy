import Foundation

/// One session of a movement, with every set it was logged with (#163).
///
/// What the statistics screen shows underneath the curve. The curve answers
/// "which way is this going"; this answers "what did I actually do", which is
/// the next question and the one the cache could already have answered all
/// along — it just took a trip through the dashboard and the right date to get
/// at it.
///
/// Carries sets the curve has no use for: a rowing machine logs distance and
/// time, a plank logs neither weight nor reps, and Epley has nothing to
/// project from either. Those sessions have no `estimatedOneRepMaxKg` and no
/// point on the chart — but they are the only thing the screen can show for
/// such a movement, so they belong in the history all the same.
// `Equatable` rather than `Hashable`: `SetDetail` is not hashable, and nothing
// here travels as a navigation value — the entry is identified by its session
// start, which is what `ForEach` needs.
struct ExerciseHistoryEntry: Equatable, Identifiable, Sendable {
    /// Start of the session, and the identity: a movement is folded to one
    /// entry per session.
    let sessionStart: Date
    /// Every set of the movement in that session, in the source's order —
    /// warm-ups included, marked as such by their type.
    let sets: [SetDetail]
    /// Epley over the session's best counted set, or `nil` when no set carried
    /// both weight and reps.
    let estimatedOneRepMaxKg: Double?
    /// The counted set the estimate came from, so the row can say how the
    /// number was reached.
    let bestSet: SetDetail?
    /// Σ (weight × reps) over the counted sets, in kg.
    let volumeKg: Double
    /// Sets that counted towards `volumeKg` (warm-ups excluded).
    let countedSetCount: Int

    var id: Date { sessionStart }

    /// The point this session contributes to the curve, when it has one.
    ///
    /// The curve is derived from the history rather than gathered beside it:
    /// two walks over the same sessions are two chances to disagree about
    /// which set was the best one.
    var progressionPoint: ProgressionPoint? {
        guard let estimatedOneRepMaxKg,
              let bestSet,
              let weightKg = bestSet.weightKg,
              let reps = bestSet.reps else { return nil }
        return ProgressionPoint(
            sessionStart: sessionStart,
            estimatedOneRepMaxKg: estimatedOneRepMaxKg,
            weightKg: weightKg,
            reps: reps
        )
    }
}

extension ExerciseHistoryEntry {
    /// Σ of the logged distances, in metres — `nil` when no set logged one.
    var totalDistanceMeters: Double? {
        let distances = sets.compactMap(\.distanceMeters)
        return distances.isEmpty ? nil : distances.reduce(0, +)
    }

    /// Σ of the logged durations, in seconds — `nil` when no set logged one.
    var totalDurationSeconds: Int? {
        let durations = sets.compactMap(\.durationSeconds)
        return durations.isEmpty ? nil : durations.reduce(0, +)
    }

    /// Σ of the logged repetitions — `nil` when no set logged any.
    var totalReps: Int? {
        let reps = sets.compactMap(\.reps)
        return reps.isEmpty ? nil : reps.reduce(0, +)
    }

    /// Builds an entry from a session's sets and derives everything that
    /// follows from them — the estimate, the best set, the volume and the
    /// counted tally.
    ///
    /// The deriving initialiser is the only one anything outside this file
    /// should reach for, for the reason `ExerciseDetail`'s is: a caller that
    /// passes its own totals is a caller that can get them wrong.
    init(sessionStart: Date, sets: [SetDetail]) {
        let countedSets = sets.filter(\.countsTowardsVolume)
        let best = countedSets
            .filter { OneRepMax.epley(of: $0) != nil }
            .max { (OneRepMax.epley(of: $0) ?? 0) < (OneRepMax.epley(of: $1) ?? 0) }

        self.init(
            sessionStart: sessionStart,
            sets: sets,
            estimatedOneRepMaxKg: best.flatMap { OneRepMax.epley(of: $0) },
            bestSet: best,
            volumeKg: countedSets.trainingVolumeKg,
            countedSetCount: countedSets.count
        )
    }
}
