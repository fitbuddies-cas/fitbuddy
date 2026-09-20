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

    /// Whether the row is better described by distance and time than by kg.
    /// This is a presentation question; the domain question — which sport was
    /// trained — is `isEnduranceWork`, which is what the analysis paths read
    /// (ADR-012).
    ///
    /// Since #180 a mapped endurance discipline is cardio whatever it logged,
    /// so a Strava `Run` no longer depends on the heuristic. Every other kind
    /// falls through to that heuristic — moved no load, but logged distance
    /// or time. A `WeightTraining` session that logged only a duration
    /// therefore still shows its time: "0 kg" would be a wrong number rather
    /// than a missing one, even though its `kind` is `.strength`.
    var isCardio: Bool {
        if kind.isEndurance { return true }
        return volumeKg == 0 && (distanceMeters != nil || durationSeconds != nil)
    }

    /// Whether the session is endurance work — the domain question, and the
    /// one rule `AnalysisDomain`, the prompt's sections and the exercise list
    /// all read, so the Exercises section can never fall out of step with the
    /// strength figures it explains (#183).
    ///
    /// It turns on whether `kind` is a classification at all:
    ///
    /// - a mapped endurance discipline is endurance whatever it logged,
    /// - `.strength` **from an endurance source** is a real classification —
    ///   Strava's `WeightTraining`, Polar's `STRENGTH_TRAINING` — so that
    ///   session is strength work even though `isCardio` shows its duration,
    /// - everything else falls back on the row's own figures: Hevy's
    ///   `.strength` is the model's default rather than a statement about the
    ///   session, so a Hevy treadmill session is endurance, and `.other` is a
    ///   row cached before V5 whose sport was never recorded.
    var isEnduranceWork: Bool {
        if kind.isEndurance { return true }
        if kind == .strength, source.isEnduranceSource { return false }
        return isCardio
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
