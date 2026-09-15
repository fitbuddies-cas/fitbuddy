import Foundation

#if DEBUG
/// In-memory `ExerciseProgressionReading` for SwiftUI previews (#42).
///
/// Debug-only: the shipped app always reads the real `WorkoutStore`. Previews
/// cannot spin up a SwiftData container per canvas, so they get plain values.
struct PreviewProgressionCache: ExerciseProgressionReading {
    /// Concrete and `Sendable`, unlike a bare `Error` existential — the
    /// protocol refines `Sendable`.
    enum Failure: Error, Sendable {
        case cacheUnavailable
    }

    let progression: ExerciseProgression?
    /// Set to render the screen's failure state.
    var failure: Failure?

    func exerciseProgression(id: String, since date: Date) async throws -> ExerciseProgression? {
        if let failure { throw failure }
        return progression
    }
}

extension PreviewProgressionCache {
    /// Estimates a week apart, oldest first.
    static func points(_ estimates: [Double]) -> [ProgressionPoint] {
        let start = Calendar.current.date(byAdding: .day, value: -7 * estimates.count, to: .now) ?? .now
        return estimates.enumerated().map { index, estimate in
            ProgressionPoint(
                sessionStart: start.addingTimeInterval(Double(index) * 7 * 86_400),
                estimatedOneRepMaxKg: estimate,
                weightKg: (estimate / 1.25).rounded(),
                reps: 8
            )
        }
    }

    static let risingPoints = points([96, 98.5, 101, 100.5, 104, 107.5])

    private static let bench = ExerciseSummary(
        id: "preview-bench",
        title: "Bench Press (Barbell)",
        muscleGroup: .chest,
        sessionCount: 6,
        countedSetCount: 24,
        volumeKg: 18_400,
        lastPerformed: .now
    )

    /// A curve that is going somewhere.
    @MainActor static var rising: ExerciseProgressionViewModel {
        makeViewModel(points: risingPoints)
    }

    /// Three sessions that never reach the old peak — the badge case (AC2).
    @MainActor static var plateaued: ExerciseProgressionViewModel {
        makeViewModel(points: points([98, 105, 102, 104, 103.5]))
    }

    /// One usable session — AC3's hint instead of a chart.
    @MainActor static var sparse: ExerciseProgressionViewModel {
        makeViewModel(points: points([101]))
    }

    @MainActor private static func makeViewModel(points: [ProgressionPoint]) -> ExerciseProgressionViewModel {
        ExerciseProgressionViewModel(
            cache: PreviewProgressionCache(
                progression: ExerciseProgression(id: bench.id, title: bench.title, points: points)
            ),
            exercise: bench
        )
    }
}
#endif
