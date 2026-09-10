import Foundation

/// Wire shape of one entry in Strava's `GET /api/v3/athlete/activities`
/// (a "SummaryActivity"), reduced to the fields `Activity` can hold (#142).
///
/// Strava has no notion of exercises and sets: an activity *is* the effort.
/// It maps onto one `ActivityExercise` titled after the sport with one
/// `ActivityExerciseSet` carrying distance and moving time — the fields
/// `ActivityExerciseSet` already had for Hevy's cardio sets, which is why the
/// `Activity` model needs no Strava-specific additions (ADR-10, ADR-6).
///
/// Only `id` and `start_date` decode strictly; everything else is optional
/// and defaults on the way to `Activity`, so one oddly-shaped activity cannot
/// fail a whole sync.
struct StravaActivityDTO: Decodable, Equatable, Sendable {
    let id: Int64
    let name: String?
    /// Strava's newer, finer sport classification (`TrailRun`, `GravelRide`).
    let sportType: String?
    /// The older, coarser one (`Run`, `Ride`); sent alongside `sport_type`.
    let type: String?
    let startDate: Date
    /// Wall-clock duration in seconds, pauses included.
    let elapsedTime: Int?
    /// Seconds spent moving — the training-relevant duration.
    let movingTime: Int?
    /// Metres.
    let distance: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sportType = "sport_type"
        case type
        case startDate = "start_date"
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case distance
    }

    /// The `Activity.id` this activity maps to. Prefixed so the source is
    /// readable off the primary key and a Strava id can never be mistaken for
    /// a Hevy one, even though the two id spaces do not overlap today.
    var activityID: String { "strava:\(id)" }

    /// Normalizes the activity (ADR-6). The only place Strava's wire shape is
    /// translated.
    func makeActivity() -> Activity {
        let sport = sportType ?? type ?? "Activity"
        return Activity(
            id: activityID,
            title: name ?? sport,
            startTime: startDate,
            endTime: elapsedTime.map { startDate.addingTimeInterval(TimeInterval($0)) },
            source: .strava,
            exercises: [
                ActivityExercise(
                    index: 0,
                    title: sport,
                    sets: [
                        ActivityExerciseSet(
                            index: 0,
                            type: .normal,
                            // Zero means "not logged" for both, as with Hevy's
                            // cardio sets: a yoga session has no distance, and
                            // 0 m on the detail screen would read as a bug.
                            distanceMeters: distance.flatMap { $0 > 0 ? $0 : nil },
                            durationSeconds: movingTime.flatMap { $0 > 0 ? $0 : nil }
                        ),
                    ]
                ),
            ]
        )
    }
}
