import Foundation

/// One logged set as returned inside `GET /v1/workouts`.
///
/// Every metric is optional in Hevy's schema — which metrics are populated
/// depends on the exercise type (weight/reps, distance/duration, or neither).
struct HevySetDTO: Decodable, Equatable, Sendable {
    let index: Int?
    let type: String?
    let weightKg: Double?
    let reps: Int?
    let distanceMeters: Double?
    let durationSeconds: Int?
    let rpe: Double?

    private enum CodingKeys: String, CodingKey {
        case index
        case type
        case weightKg = "weight_kg"
        case reps
        case distanceMeters = "distance_meters"
        case durationSeconds = "duration_seconds"
        case rpe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeLooseIntIfPresent(forKey: .index)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        reps = try container.decodeLooseIntIfPresent(forKey: .reps)
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters)
        durationSeconds = try container.decodeLooseIntIfPresent(forKey: .durationSeconds)
        rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
    }

    /// Maps to the cached model. `fallbackIndex` preserves the payload order
    /// when Hevy omits `index`.
    func makeExerciseSet(fallbackIndex: Int) -> ExerciseSet {
        ExerciseSet(
            index: index ?? fallbackIndex,
            type: SetType.from(type),
            weightKg: weightKg,
            reps: reps,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            rpe: rpe
        )
    }
}
