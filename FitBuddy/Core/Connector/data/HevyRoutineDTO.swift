import Foundation

/// A routine as returned by `GET /v1/routines` — the plan a workout was
/// logged against, which is where the rep targets of US-17 come from (#240).
///
/// Only `id` is decoded strictly: it is what `HevyWorkoutDTO.routineID` joins
/// on. Everything else is optional so a routine with an odd exercise still
/// contributes its targets.
struct HevyRoutineDTO: Decodable, Equatable, Sendable {
    let id: String
    let title: String?
    let updatedAt: Date?
    let exercises: [HevyRoutineExerciseDTO]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case updatedAt = "updated_at"
        case exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        exercises = try container.decodeIfPresent([HevyRoutineExerciseDTO].self, forKey: .exercises) ?? []
    }

    /// The routine exercise a logged exercise was performed against: the
    /// `occurrence`-th entry (zero-based) sharing its `exercise_template_id`.
    ///
    /// The template id is the movement's identity across the two payloads;
    /// the occurrence disambiguates a routine that lists the same movement
    /// twice (a heavy block and a back-off block of the same squat), where
    /// the first logged one belongs to the first prescribed one. `nil` when
    /// the routine does not prescribe the movement — the user swapped an
    /// exercise on the day — or not that many times.
    func exercise(templateID: String, occurrence: Int) -> HevyRoutineExerciseDTO? {
        let matches = exercises.filter { $0.exerciseTemplateID == templateID }
        return matches.indices.contains(occurrence) ? matches[occurrence] : nil
    }
}
