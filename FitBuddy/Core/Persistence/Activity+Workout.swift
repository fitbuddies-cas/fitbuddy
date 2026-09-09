import Foundation

/// Maps the normalized connector model onto the cached SwiftData hierarchy
/// (ADR-6, #34).
///
/// The cache is written from `Activity`, never from a provider's own DTOs, so
/// a second source (#35) reaches SwiftData through exactly this mapping
/// instead of bringing its own. It lives in the persistence layer rather than
/// the connector one for the same reason: `Workout` is what this app stores,
/// not what a provider delivers.
extension Activity {
    func makeWorkout() -> Workout {
        Workout(
            id: id,
            title: title,
            workoutDescription: notes,
            startTime: startTime,
            endTime: endTime,
            updatedAt: updatedAt,
            exercises: exercises.map { $0.makeExercise() }
        )
    }
}

extension ActivityExercise {
    func makeExercise() -> Exercise {
        Exercise(
            index: index,
            title: title,
            notes: notes,
            templateID: templateID,
            supersetID: supersetID,
            sets: sets.map { $0.makeExerciseSet() }
        )
    }
}

extension ActivityExerciseSet {
    func makeExerciseSet() -> ExerciseSet {
        ExerciseSet(
            index: index,
            type: type,
            weightKg: weightKg,
            reps: reps,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            rpe: rpe
        )
    }
}
