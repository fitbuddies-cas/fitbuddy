import Foundation

/// One exercise of a workout as returned inside `GET /v1/workouts`.
struct HevyExerciseDTO: Decodable, Equatable, Sendable {
    let title: String?
    let notes: String?
    let exerciseTemplateID: String?
    let supersetsID: Int?
    let sets: [HevySetDTO]

    private enum CodingKeys: String, CodingKey {
        case title
        case notes
        case exerciseTemplateID = "exercise_template_id"
        case supersetsID = "supersets_id"
        case sets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        exerciseTemplateID = try container.decodeIfPresent(String.self, forKey: .exerciseTemplateID)
        supersetsID = try container.decodeLooseIntIfPresent(forKey: .supersetsID)
        sets = try container.decodeIfPresent([HevySetDTO].self, forKey: .sets) ?? []
    }

    /// Maps to the normalized model, ordered by `position` in the payload.
    ///
    /// The payload position, not Hevy's own `index` field: that field is
    /// optional, so a payload may carry it for some entries and omit it for
    /// others, and mixing the two produces duplicates — `ActivityExercise.id`
    /// is this index, so a collision makes `ForEach` drop a card and leaves
    /// the sort by index arbitrary. The position is unique by construction and
    /// is Hevy's order, which is what the index was read for.
    ///
    /// - Parameter prescribed: The routine exercise this one was performed
    ///   against (#240); its set targets are matched per kind — the k-th
    ///   logged warm-up to the k-th prescribed one, the k-th working set to
    ///   the k-th prescribed working set. `nil` when the workout had no
    ///   routine or the routine did not list the movement.
    func makeActivityExercise(position: Int, prescribed: HevyRoutineExerciseDTO? = nil) -> ActivityExercise {
        var ordinals = (warmUp: 0, working: 0)
        let activitySets = sets.enumerated().map { position, set -> ActivityExerciseSet in
            let warmUp = SetType.from(set.type) == .warmup
            let ordinal: Int
            if warmUp {
                ordinal = ordinals.warmUp
                ordinals.warmUp += 1
            } else {
                ordinal = ordinals.working
                ordinals.working += 1
            }
            return set.makeActivitySet(
                position: position,
                targetReps: prescribed?.targetReps(forSet: ordinal, warmUp: warmUp)
            )
        }
        ActivityExercise(
            index: position,
            // An untitled exercise is not worth dropping the workout for; the
            // template id still identifies the movement for US-9.
            title: title ?? "Unknown exercise",
            notes: notes,
            templateID: exerciseTemplateID,
            supersetID: supersetsID,
            sets: activitySets
        )
    }
}
