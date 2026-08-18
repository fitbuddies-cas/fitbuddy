import Foundation

/// One exercise of a workout as returned inside `GET /v1/workouts`.
struct HevyExerciseDTO: Decodable, Equatable, Sendable {
    let index: Int?
    let title: String?
    let notes: String?
    let exerciseTemplateID: String?
    let supersetsID: Int?
    let sets: [HevySetDTO]

    private enum CodingKeys: String, CodingKey {
        case index
        case title
        case notes
        case exerciseTemplateID = "exercise_template_id"
        case supersetsID = "supersets_id"
        case sets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeLooseIntIfPresent(forKey: .index)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        exerciseTemplateID = try container.decodeIfPresent(String.self, forKey: .exerciseTemplateID)
        supersetsID = try container.decodeLooseIntIfPresent(forKey: .supersetsID)
        sets = try container.decodeIfPresent([HevySetDTO].self, forKey: .sets) ?? []
    }

    /// Maps to the cached model. `fallbackIndex` preserves the payload order
    /// when Hevy omits `index`.
    func makeExercise(fallbackIndex: Int) -> Exercise {
        Exercise(
            index: index ?? fallbackIndex,
            // An untitled exercise is not worth dropping the workout for; the
            // template id still identifies the movement for US-9.
            title: title ?? "Unknown exercise",
            notes: notes,
            templateID: exerciseTemplateID,
            supersetID: supersetsID,
            sets: sets.enumerated().map { $0.element.makeExerciseSet(fallbackIndex: $0.offset) }
        )
    }
}
