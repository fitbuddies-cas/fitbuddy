import Foundation

#if DEBUG
/// In-memory `WorkoutSummaryReading` for SwiftUI previews.
///
/// Debug-only: the shipped app always reads the real `WorkoutStore`. Previews
/// cannot spin up a SwiftData container per canvas, so they get plain values.
struct PreviewWorkoutCache: WorkoutSummaryReading {
    /// Concrete and `Sendable`, unlike a bare `Error` existential: the protocol
    /// refines `Sendable`, and under Swift 6 the existential would stop
    /// compiling rather than just warning.
    enum Failure: Error, Sendable {
        case cacheUnavailable
    }

    let summaries: [WorkoutSummary]
    /// Set to render the dashboard's failure state.
    var failure: Failure?

    func workoutSummaries(since date: Date) async throws -> [WorkoutSummary] {
        if let failure { throw failure }
        return summaries.filter { $0.startTime >= date }
    }
}

extension PreviewWorkoutCache {
    /// Six weeks of a four-day split, newest first.
    static let filled = PreviewWorkoutCache(summaries: (0..<24).map { index in
        let plan = plans[index % plans.count]
        // Volume creeps up towards the newest session, so the numbers read like
        // a training block rather than noise.
        let progression = 1 - Double(index) * 0.008
        return WorkoutSummary(
            id: "preview-\(index)",
            title: plan.title,
            startTime: Calendar.current.date(byAdding: .day, value: -index * 2, to: .now) ?? .now,
            volumeKg: plan.volumeKg * progression,
            exerciseCount: plan.loads.count,
            countedSetCount: plan.loads.reduce(0) { $0 + $1.setCount },
            muscleLoads: plan.loads.map {
                MuscleLoad(group: $0.group, volumeKg: $0.volumeKg * progression, setCount: $0.setCount)
            }
        )
    })

    static let empty = PreviewWorkoutCache(summaries: [])

    private static let plans: [(title: String, volumeKg: Double, loads: [MuscleLoad])] = [
        ("Push Day", 9_150, [
            MuscleLoad(group: .chest, volumeKg: 5_400, setCount: 10),
            MuscleLoad(group: .shoulders, volumeKg: 2_450, setCount: 7),
            MuscleLoad(group: .arms, volumeKg: 1_300, setCount: 4),
        ]),
        ("Pull Day", 10_400, [
            MuscleLoad(group: .back, volumeKg: 8_100, setCount: 13),
            MuscleLoad(group: .arms, volumeKg: 2_300, setCount: 6),
        ]),
        ("Leg Day", 14_900, [
            MuscleLoad(group: .legs, volumeKg: 14_900, setCount: 18),
        ]),
        ("Conditioning & Core", 0, [
            MuscleLoad(group: .core, volumeKg: 0, setCount: 6),
            MuscleLoad(group: .other, volumeKg: 0, setCount: 2),
        ]),
    ]
}
#endif
