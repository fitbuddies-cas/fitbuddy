import Foundation

/// One logged set as returned inside `GET /v1/workouts`.
///
/// Every metric is optional in Hevy's schema — which metrics are populated
/// depends on the exercise type (weight/reps, distance/duration, or neither).
struct HevySetDTO: Decodable, Equatable, Sendable {
    let type: String?
    let weightKg: Double?
    let reps: Int?
    let distanceMeters: Double?
    let durationSeconds: Int?
    let rpe: Double?

    private enum CodingKeys: String, CodingKey {
        case type
        case weightKg = "weight_kg"
        case reps
        case distanceMeters = "distance_meters"
        case durationSeconds = "duration_seconds"
        case rpe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        reps = try container.decodeLooseIntIfPresent(forKey: .reps)
        distanceMeters = Self.droppingZero(try container.decodeIfPresent(Double.self, forKey: .distanceMeters))
        durationSeconds = Self.droppingZero(try container.decodeLooseIntIfPresent(forKey: .durationSeconds))
        rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
    }

    /// Reads a `0` distance or duration as "not logged".
    ///
    /// Hevy sends `0` rather than `null` for the metrics an exercise does not
    /// use — a machine set arrives as `distance_meters: 0, duration_seconds: 0`
    /// alongside its weight and reps. Kept as zeros they are indistinguishable
    /// from logged values: the detail row prints `0 m · 0:00` on a strength
    /// set, and the `Activity` mapping below would carry the same phantom
    /// values into the normalized model.
    ///
    /// Only these two metrics: `0 kg` is a bodyweight set and `0 reps` a set
    /// that was started and not completed — both are statements, not gaps.
    private static func droppingZero<Value: Numeric>(_ value: Value?) -> Value? {
        value == 0 ? nil : value
    }

    /// Maps to the normalized model, ordered by `position` in the payload.
    ///
    /// As for the exercise above: Hevy's own `index` is optional, and mixing it
    /// with a positional fallback yields duplicate ids.
    func makeActivitySet(position: Int) -> ActivityExerciseSet {
        ActivityExerciseSet(
            index: position,
            type: SetType.from(type),
            weightKg: weightKg,
            reps: reps,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            rpe: rpe
        )
    }
}
