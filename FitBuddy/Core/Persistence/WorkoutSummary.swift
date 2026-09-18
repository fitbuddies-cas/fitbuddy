import Foundation
import SwiftData

/// A cached workout reduced to the `Sendable` values the dashboard shows.
///
/// `WorkoutStore` hands these out instead of `@Model` instances: a `Workout`
/// is bound to its `ModelContext` and cannot cross an actor boundary, so the
/// aggregation happens where the models live and only value types travel.
/// `Hashable` so the dashboard can push a row as a `NavigationLink` value
/// (#98): the detail screen is addressed by the summary the user tapped, and
/// `.navigationDestination(for:)` builds its ViewModel once per push instead
/// of once per rendered row.
struct WorkoutSummary: Hashable, Identifiable, Sendable {
    /// The source's workout id.
    let id: String
    let title: String
    let startTime: Date
    /// Which provider delivered the session (#141) — the dashboard labels
    /// Strava sessions next to Hevy ones (US-5 AC1).
    let source: ConnectorSource
    /// The normalized sport (#180). `.strength` for a Hevy workout, and for a
    /// cached session written before V5 whose sport nobody recorded.
    let kind: ActivityKind
    /// Training volume in kg: Σ (weight × reps) over all counted sets.
    let volumeKg: Double
    let exerciseCount: Int
    /// Sets that counted towards `volumeKg` (warm-ups excluded).
    let countedSetCount: Int
    /// The workout's volume split by muscle group, one entry per group it
    /// loaded. Feeds the dashboard's distribution chart (#27). Empty for a
    /// Strava session — see `init(workout:)`.
    let muscleLoads: [MuscleLoad]
    /// Σ distance over the counted sets, in metres, or `nil` when none logged
    /// one (#144). A run has this and no volume; a bench session the reverse.
    let distanceMeters: Double?
    /// Σ duration over the counted sets, in seconds, or `nil` when none logged
    /// one (#144).
    let durationSeconds: Int?
    /// Session-level endurance metrics the source reported (#180) — heart
    /// rate, elevation, speed, effort. `nil` for a strength session and for
    /// any session cached before V5.
    let cardio: CardioMetrics?

    /// - Parameters:
    ///   - source: Defaults to Hevy, so a fixture written before #141 still
    ///     describes what it always did.
    ///   - muscleLoads: Defaults to none, so a caller that only cares about
    ///     the totals — a test fixture, a list row — stays unaffected, as it
    ///     does for `kind` and `cardio`.
    ///   - distanceMeters: Defaults to none, as does `durationSeconds`, for
    ///     the same reason.
    init(
        id: String,
        title: String,
        startTime: Date,
        source: ConnectorSource = .hevy,
        kind: ActivityKind = .strength,
        volumeKg: Double,
        exerciseCount: Int,
        countedSetCount: Int,
        muscleLoads: [MuscleLoad] = [],
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil,
        cardio: CardioMetrics? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.source = source
        self.kind = kind
        self.volumeKg = volumeKg
        self.exerciseCount = exerciseCount
        self.countedSetCount = countedSetCount
        self.muscleLoads = muscleLoads
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.cardio = cardio
    }

    /// Whether the session is better described by distance and time than by
    /// kg. Since #180 `kind` decides this wherever it was actually mapped,
    /// and the old heuristic — moved no load, but logged distance or time —
    /// is only the fallback where it was not.
    ///
    /// Two kinds are authoritative. An endurance discipline is cardio
    /// whatever it logged, so a Strava `WeightTraining` session no longer
    /// reads as a run just because it moved no barbell. `.strength` rules the
    /// session out only when an endurance source mapped it from its own
    /// vocabulary (`WeightTraining`, `STRENGTH_TRAINING`) — Hevy's
    /// `.strength` is the model's default rather than a classification, so it
    /// says nothing, and a Hevy session of treadmill sets still falls through
    /// to the heuristic.
    ///
    /// `.other` falls through as well. That is what a row cached before V5
    /// reads as, where the sport was never recorded (see `Workout.kind`).
    var isCardio: Bool {
        if kind.isEndurance { return true }
        if kind == .strength, source.isEnduranceSource { return false }
        return volumeKg == 0 && (distanceMeters != nil || durationSeconds != nil)
    }
}

extension WorkoutSummary {
    /// Reduces a cached workout. Must be called on the actor owning `workout`.
    init(workout: Workout) {
        let countedSets = workout.exercises
            .flatMap(\.sets)
            .filter { $0.type.countsTowardsVolume }

        // Per exercise, so the muscle group is decided once per movement and
        // the split adds up to the workout's own volume.
        let loads = workout.exercises.map { exercise -> MuscleLoad in
            let sets = exercise.sets.filter { $0.type.countsTowardsVolume }
            return MuscleLoad(
                group: MuscleGroup.from(exerciseTitle: exercise.title),
                volumeKg: sets.trainingVolumeKg,
                setCount: sets.count
            )
        }

        let distance = countedSets.compactMap(\.distanceMeters).reduce(0, +)
        let duration = countedSets.compactMap(\.durationSeconds).reduce(0, +)

        self.init(
            id: workout.id,
            title: workout.title,
            startTime: workout.startTime,
            source: workout.source,
            kind: workout.kind,
            volumeKg: countedSets.trainingVolumeKg,
            exerciseCount: workout.exercises.count,
            countedSetCount: countedSets.count,
            // A Strava or Polar activity is one whole-body effort, not a set of
            // movements with muscle groups (#144, US-5 AC1): listing a run as
            // "Other · 1 set" would misrepresent both the run and the chart,
            // which stays what it was — Hevy's strength split.
            muscleLoads: workout.source.isEnduranceSource ? [] : MuscleLoad.merged(loads),
            // A source that reports no sets (Polar) carries its distance and
            // duration in the cardio block instead, so the dashboard reads the
            // same two figures whichever source wrote the session.
            distanceMeters: distance > 0 ? distance : workout.cardio?.distanceMeters,
            durationSeconds: duration > 0 ? duration : workout.cardio?.durationSeconds,
            cardio: workout.cardio
        )
    }
}
