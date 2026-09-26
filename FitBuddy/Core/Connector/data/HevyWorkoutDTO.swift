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
    /// The routine the workout was started from, when it was (#240).
    ///
    /// Optional although the spec does not mark it nullable: a workout the
    /// user logged without a routine cannot carry one, and a non-optional
    /// field would fail the decode of the whole page at the first free
    /// workout.
    let routineID: String?
    let exercises: [HevyExerciseDTO]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case routineID = "routine_id"
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
        routineID = try container.decodeIfPresent(String.self, forKey: .routineID)
        exercises = try container.decodeIfPresent([HevyExerciseDTO].self, forKey: .exercises) ?? []
    }

    /// Maps to the normalized `Activity` (ADR-6), including its exercises and
    /// sets. This is the only place Hevy's wire shape is translated — every
    /// layer above the connector reads `Activity`.
    ///
    /// - Parameter routine: The routine `routineID` names, when the connector
    ///   could fetch it (#240). Its targets are snapshotted onto the sets
    ///   here, at sync time: a routine has no version history, so joining it
    ///   later would compare the session against a plan that may since have
    ///   changed. `nil` — no routine, or one Hevy no longer has — leaves
    ///   every target empty, which is a state and not a failure.
    func makeActivity(routine: HevyRoutineDTO? = nil) -> Activity {
        // The n-th logged occurrence of a movement is matched to the n-th
        // prescribed one, so a routine listing the same squat twice hands each
        // block its own targets rather than the first block's to both.
        var occurrences: [String: Int] = [:]
        let activityExercises = exercises.enumerated().map { position, exercise -> ActivityExercise in
            var prescribed: HevyRoutineExerciseDTO?
            if let routine, let templateID = exercise.exerciseTemplateID {
                let occurrence = occurrences[templateID, default: 0]
                occurrences[templateID] = occurrence + 1
                prescribed = routine.exercise(templateID: templateID, occurrence: occurrence)
            }
            return exercise.makeActivityExercise(position: position, prescribed: prescribed)
        }
        return Activity(
            id: id,
            title: title ?? "Workout",
            notes: description,
            startTime: startTime,
            endTime: endTime,
            updatedAt: updatedAt,
            source: .hevy,
            exercises: activityExercises,
            routineID: routineID,
            routineUpdatedAt: routine?.updatedAt
        )
    }
}
