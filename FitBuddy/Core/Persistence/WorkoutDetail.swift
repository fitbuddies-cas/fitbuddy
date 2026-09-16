import Foundation

/// One cached workout with its full exercise tree — the `Sendable` projection
/// behind the workout detail screen (#98).
///
/// The counterpart to `WorkoutSummary`, which flattens the same session into
/// `exerciseCount` / `countedSetCount` for the dashboard list. Both exist
/// because a `Workout` is bound to its `ModelContext` and cannot leave
/// `WorkoutStore`; what differs is how much of the tree the screen needs, and
/// loading the whole tree for 90 sessions to render ten rows would be waste.
struct WorkoutDetail: Equatable, Identifiable, Sendable {
    /// The source's workout id.
    let id: String
    let title: String
    /// The source's free-text description of the session, if the user wrote one.
    let workoutDescription: String?
    let startTime: Date
    /// Which provider delivered the session (#141).
    let source: ConnectorSource
    /// `nil` for a session Hevy never closed — the screen then shows no
    /// duration rather than an invented one.
    let endTime: Date?
    /// Training volume in kg: Σ (weight × reps) over all counted sets.
    let volumeKg: Double
    /// Sets that counted towards `volumeKg` (warm-ups excluded).
    let countedSetCount: Int
    /// The session's exercises in Hevy's order, each with its sets.
    let exercises: [ExerciseDetail]

    /// How many exercises the session held — the same figure the dashboard row
    /// shows, read off the list rather than stored twice.
    var exerciseCount: Int { exercises.count }

    /// - Parameter source: Defaults to Hevy, so a fixture written before #141
    ///   still describes what it always did.
    init(
        id: String,
        title: String,
        workoutDescription: String?,
        startTime: Date,
        endTime: Date?,
        source: ConnectorSource = .hevy,
        volumeKg: Double,
        countedSetCount: Int,
        exercises: [ExerciseDetail]
    ) {
        self.id = id
        self.title = title
        self.workoutDescription = workoutDescription
        self.startTime = startTime
        self.endTime = endTime
        self.source = source
        self.volumeKg = volumeKg
        self.countedSetCount = countedSetCount
        self.exercises = exercises
    }
}

extension WorkoutDetail {
    /// Reduces a cached workout and its whole tree, sorting the exercises by
    /// `index`.
    ///
    /// As in `ExerciseDetail`, the sort is what makes the screen match Hevy:
    /// SwiftData does not guarantee the order of a to-many relationship.
    ///
    /// Must be called on the actor owning `workout`.
    init(workout: Workout) {
        let exercises = workout.exercises
            .sorted { $0.index < $1.index }
            .map(ExerciseDetail.init(exercise:))

        self.init(
            id: workout.id,
            title: workout.title,
            workoutDescription: workout.workoutDescription,
            startTime: workout.startTime,
            endTime: workout.endTime,
            source: workout.source,
            // Summed from the exercises rather than from a second walk over
            // the tree, so the header can never contradict the cards under it.
            volumeKg: exercises.reduce(0) { $0 + $1.volumeKg },
            countedSetCount: exercises.reduce(0) { $0 + $1.countedSetCount },
            exercises: exercises
        )
    }
}
