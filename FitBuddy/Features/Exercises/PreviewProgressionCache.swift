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
    /// Sessions a week apart, oldest first: a warm-up and two working sets.
    ///
    /// The values seed the working load, so the estimates the screen shows come
    /// out somewhat higher — they are what Epley makes of eight reps at that
    /// weight, exactly as they would from real data.
    static func sessions(_ estimates: [Double]) -> [ExerciseHistoryEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -7 * estimates.count, to: .now) ?? .now
        return estimates.enumerated().map { index, estimate in
            let working = (estimate / 1.25).rounded()
            return ExerciseHistoryEntry(
                sessionStart: start.addingTimeInterval(Double(index) * 7 * 86_400),
                sets: [
                    SetDetail(index: 0, type: .warmup, weightKg: working * 0.6, reps: 10,
                              distanceMeters: nil, durationSeconds: nil, rpe: nil),
                    SetDetail(index: 1, type: .normal, weightKg: working, reps: 8,
                              distanceMeters: nil, durationSeconds: nil, rpe: nil),
                    SetDetail(index: 2, type: .normal, weightKg: working, reps: 7,
                              distanceMeters: nil, durationSeconds: nil, rpe: 8.5),
                ]
            )
        }
    }

    /// A movement Epley cannot project from — the case the history exists for:
    /// no curve, but the sessions are still there to read (#163).
    static func cardioSessions(_ count: Int) -> [ExerciseHistoryEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -7 * count, to: .now) ?? .now
        return (0..<count).map { index in
            ExerciseHistoryEntry(
                sessionStart: start.addingTimeInterval(Double(index) * 7 * 86_400),
                sets: [
                    SetDetail(index: 0, type: .normal, weightKg: nil, reps: nil,
                              distanceMeters: 2_000 + Double(index) * 150, durationSeconds: 480,
                              rpe: nil),
                ]
            )
        }
    }

    static let risingPoints = sessions([96, 98.5, 101, 100.5, 104, 107.5]).compactMap(\.progressionPoint)

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
        makeViewModel(sessions: sessions([96, 98.5, 101, 100.5, 104, 107.5]))
    }

    /// Three sessions that never reach the old peak — the badge case (AC2).
    @MainActor static var plateaued: ExerciseProgressionViewModel {
        makeViewModel(sessions: sessions([98, 105, 102, 104, 103.5]))
    }

    /// One usable session — AC3's hint instead of a chart.
    @MainActor static var sparse: ExerciseProgressionViewModel {
        makeViewModel(sessions: sessions([101]))
    }

    /// Rowing: sessions to read, no curve to draw (#163).
    @MainActor static var cardio: ExerciseProgressionViewModel {
        makeViewModel(sessions: cardioSessions(4), title: "Rowing Machine")
    }

    @MainActor private static func makeViewModel(
        sessions: [ExerciseHistoryEntry],
        title: String? = nil
    ) -> ExerciseProgressionViewModel {
        ExerciseProgressionViewModel(
            cache: PreviewProgressionCache(
                progression: ExerciseProgression(
                    id: bench.id,
                    title: title ?? bench.title,
                    sessions: sessions
                )
            ),
            exercise: ExerciseIdentity(
                id: bench.id,
                title: title ?? bench.title,
                muscleGroup: MuscleGroup.from(exerciseTitle: title ?? bench.title)
            )
        )
    }
}
#endif
