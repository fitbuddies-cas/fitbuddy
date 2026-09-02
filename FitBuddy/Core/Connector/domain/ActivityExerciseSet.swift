import Foundation

/// A single logged set, the leaf of the `Activity → ActivityExercise →
/// ActivityExerciseSet` hierarchy.
///
/// Every metric is optional because a source logs only what the exercise
/// type requires: a barbell set has weight and reps, a treadmill set has
/// distance and duration, a bodyweight set has neither weight nor distance.
struct ActivityExerciseSet: Identifiable, Equatable, Codable, Sendable {
    /// Position of the set within its exercise, as reported by the source.
    /// Doubles as the `Identifiable` id, for the same stability reason as
    /// `ActivityExercise.index`.
    var index: Int
    /// Raw source set type — read it through `type`. Stored raw rather than
    /// `SetType` itself: a value a source adds later then decodes to
    /// `.unknown` instead of failing the whole sync (same reasoning as the
    /// cached `ExerciseSet`).
    var typeRawValue: String
    var weightKg: Double?
    var reps: Int?
    var distanceMeters: Double?
    var durationSeconds: Int?
    /// Rate of perceived exertion (6–10) when the user logged it.
    var rpe: Double?

    var id: Int { index }

    init(
        index: Int,
        type: SetType,
        weightKg: Double? = nil,
        reps: Int? = nil,
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil,
        rpe: Double? = nil
    ) {
        self.index = index
        self.typeRawValue = type.rawValue
        self.weightKg = weightKg
        self.reps = reps
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.rpe = rpe
    }

    /// Typed view of `typeRawValue`.
    var type: SetType {
        SetType.from(typeRawValue)
    }
}
