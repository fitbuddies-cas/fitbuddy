import Foundation

#if DEBUG
/// In-memory `ExerciseSummaryReading` for SwiftUI previews (#37).
///
/// Debug-only: the shipped app always reads the real `WorkoutStore`. Previews
/// cannot spin up a SwiftData container per canvas, so they get plain values.
struct PreviewExerciseCache: ExerciseSummaryReading {
    /// Concrete and `Sendable`, unlike a bare `Error` existential — the
    /// protocol refines `Sendable`.
    enum Failure: Error, Sendable {
        case cacheUnavailable
    }

    let exercises: [ExerciseSummary]
    /// Set to render the list's failure state.
    var failure: Failure?

    func exerciseSummaries(since date: Date) async throws -> [ExerciseSummary] {
        if let failure { throw failure }
        return exercises.filter { $0.lastPerformed >= date }
    }
}

extension PreviewExerciseCache {
    /// A four-day split's movements, most recently performed first.
    static let filled = PreviewExerciseCache(exercises: catalogue.enumerated().map { index, entry in
        ExerciseSummary(
            id: "preview-\(index)",
            title: entry.title,
            muscleGroup: MuscleGroup.from(exerciseTitle: entry.title),
            sessionCount: entry.sessions,
            countedSetCount: entry.sessions * 4,
            volumeKg: entry.volumeKg,
            lastPerformed: Calendar.current.date(byAdding: .day, value: -index, to: .now) ?? .now
        )
    })

    static let empty = PreviewExerciseCache(exercises: [])

    private static let catalogue: [(title: String, sessions: Int, volumeKg: Double)] = [
        ("Bench Press (Barbell)", 9, 42_180),
        ("Squat (Barbell)", 8, 61_400),
        ("Lat Pulldown (Cable)", 9, 28_900),
        ("Overhead Press (Barbell)", 7, 15_600),
        ("Romanian Deadlift (Barbell)", 6, 38_250),
        ("Bicep Curl (Dumbbell)", 8, 9_840),
        ("Plank", 5, 0),
        ("Treadmill Running", 4, 0),
    ]
}
#endif
