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

    /// - Parameters:
    ///   - source: Defaults to Hevy, so a fixture written before #141 still
    ///     describes what it always did.
    ///   - muscleLoads: Defaults to none, so a caller that only cares about
    ///     the totals — a test fixture, a list row — stays unaffected.
    ///   - distanceMeters: Defaults to none, as does `durationSeconds`, for
    ///     the same reason.
    init(
        id: String,
        title: String,
        startTime: Date,
        source: ConnectorSource = .hevy,
        volumeKg: Double,
        exerciseCount: Int,
        countedSetCount: Int,
        muscleLoads: [MuscleLoad] = [],
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.source = source
        self.volumeKg = volumeKg
        self.exerciseCount = exerciseCount
        self.countedSetCount = countedSetCount
        self.muscleLoads = muscleLoads
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }

    /// Whether the session is better described by distance and time than by
    /// kg: it moved no load but logged either. A Strava run, or a Hevy
    /// session made of treadmill sets.
    var isCardio: Bool {
        volumeKg == 0 && (distanceMeters != nil || durationSeconds != nil)
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
            volumeKg: countedSets.trainingVolumeKg,
            exerciseCount: workout.exercises.count,
            countedSetCount: countedSets.count,
            // A Strava activity is one whole-body effort, not a set of
            // movements with muscle groups (#144, US-5 AC1): listing a run as
            // "Other · 1 set" would misrepresent both the run and the chart,
            // which stays what it was — Hevy's strength split.
            muscleLoads: workout.source == .strava ? [] : MuscleLoad.merged(loads),
            distanceMeters: distance > 0 ? distance : nil,
            durationSeconds: duration > 0 ? duration : nil
        )
    }
}
