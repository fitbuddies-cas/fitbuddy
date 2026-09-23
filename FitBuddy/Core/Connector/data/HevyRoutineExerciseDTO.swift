import Foundation

/// One exercise of a routine inside `GET /v1/routines`, holding its
/// prescribed sets.
struct HevyRoutineExerciseDTO: Decodable, Equatable, Sendable {
    let title: String?
    let exerciseTemplateID: String?
    let sets: [HevyRoutineSetDTO]

    private enum CodingKeys: String, CodingKey {
        case title
        case exerciseTemplateID = "exercise_template_id"
        case sets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        exerciseTemplateID = try container.decodeIfPresent(String.self, forKey: .exerciseTemplateID)
        sets = try container.decodeIfPresent([HevyRoutineSetDTO].self, forKey: .sets) ?? []
    }

    /// The target of the prescribed set at `position`, or `nil` when the
    /// routine prescribes fewer sets than the workout logged — an extra set
    /// the user added on the day had no target to beat.
    ///
    /// By position over *all* sets, warm-ups included: Hevy lists a routine's
    /// sets in the order the workout logs them, and the logged warm-up sits at
    /// the same slot as the prescribed one. Dropping warm-ups on one side only
    /// would shift every target by one.
    func targetReps(atPosition position: Int) -> Int? {
        sets.indices.contains(position) ? sets[position].targetReps : nil
    }
}
