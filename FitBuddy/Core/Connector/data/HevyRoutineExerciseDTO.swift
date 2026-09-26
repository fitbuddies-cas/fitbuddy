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

    /// The target of the `ordinal`-th prescribed set of its kind — warm-up
    /// or working — or `nil` when the routine prescribes fewer sets of that
    /// kind than the workout logged: an extra set the user added on the day
    /// had no target to beat.
    ///
    /// Matched **per kind**, not by raw position: a warm-up the user skipped
    /// or added on the day would otherwise shift every working target by one
    /// slot, and the working sets are the ones the 2-for-2 rule reads. The
    /// k-th logged working set is compared against the k-th prescribed
    /// working set whatever happened to the warm-ups around them.
    func targetReps(forSet ordinal: Int, warmUp: Bool) -> Int? {
        let kind = sets.filter { ($0.setType == .warmup) == warmUp }
        return kind.indices.contains(ordinal) ? kind[ordinal].targetReps : nil
    }
}
