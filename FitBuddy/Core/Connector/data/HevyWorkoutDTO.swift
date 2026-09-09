import Foundation

/// A workout as returned by `GET /v1/workouts`.
///
/// Only `id` and `start_time` are decoded strictly: the id identifies the
/// workout and the start time decides whether it falls inside the 90-day
/// window (US-2). Everything else is optional so a partially filled workout
/// still reaches the cache.
struct HevyWorkoutDTO: Decodable, Equatable, Sendable {
    let id: String
    let title: String?
    let description: String?
    let startTime: Date
    let endTime: Date?
    let updatedAt: Date?
    let exercises: [HevyExerciseDTO]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case startTime = "start_time"
        case endTime = "end_time"
        case updatedAt = "updated_at"
        case exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        exercises = try container.decodeIfPresent([HevyExerciseDTO].self, forKey: .exercises) ?? []
    }

    /// Maps to the normalized `Activity` (ADR-6), including its exercises and
    /// sets. This is the only place Hevy's wire shape is translated — every
    /// layer above the connector reads `Activity`.
    func makeActivity() -> Activity {
        Activity(
            id: id,
            title: title ?? "Workout",
            notes: description,
            startTime: startTime,
            endTime: endTime,
            updatedAt: updatedAt,
            exercises: exercises.enumerated().map {
                $0.element.makeActivityExercise(position: $0.offset)
            }
        )
    }
}
