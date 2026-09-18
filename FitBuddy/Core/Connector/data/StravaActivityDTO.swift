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
    /// Cumulative ascent in metres.
    let totalElevationGain: Double?
    /// Metres per second, averaged over the moving time.
    let averageSpeed: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    /// Mechanical work in kilojoules — rides with a power meter only.
    let kilojoules: Double?
    /// Strava's Relative Effort score.
    let sufferScore: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sportType = "sport_type"
        case type
        case startDate = "start_date"
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case distance
        case totalElevationGain = "total_elevation_gain"
        case averageSpeed = "average_speed"
        case averageHeartRate = "average_heartrate"
        case maxHeartRate = "max_heartrate"
        case kilojoules
        case sufferScore = "suffer_score"
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
            kind: Self.kind(sportType: sportType, type: type),
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
            ],
            cardio: cardioMetrics()
        )
    }

    /// Strava's session metrics, or `nil` when the activity carries none —
    /// distance and moving time stay on the set, where the dashboard already
    /// reads them.
    private func cardioMetrics() -> CardioMetrics? {
        CardioMetrics(
            averageHeartRate: averageHeartRate.map { Int($0.rounded()) },
            maxHeartRate: maxHeartRate.map { Int($0.rounded()) },
            // Zero means "not logged" here as it does for distance above:
            // Strava sends 0 for an activity it never measured spatially, and
            // "0 m of ascent" on a pool swim would read as a bug.
            elevationGainMeters: totalElevationGain.flatMap { $0 > 0 ? $0 : nil },
            averageSpeedMetersPerSecond: averageSpeed.flatMap { $0 > 0 ? $0 : nil },
            energyKilojoules: kilojoules.flatMap { $0 > 0 ? $0 : nil },
            // Zero for the same reason: a block whose only content is
            // "effort 0" is not cardio data.
            perceivedEffort: sufferScore.flatMap { $0 > 0 ? $0 : nil }
        ).nonEmpty
    }

    /// Maps Strava's sport vocabulary onto `ActivityKind` — the only place it
    /// happens (#180).
    ///
    /// Matched on the suffix of the lowercased `sport_type`, because Strava's
    /// finer classification composes its names from the coarse one:
    /// `TrailRun`, `VirtualRun`, `GravelRide`, `EMountainBikeRide` all end in
    /// the discipline they belong to. That keeps a sport Strava adds later
    /// classified instead of dropping it into `.other` until someone extends
    /// a lookup table. `type` is the fallback for a payload that predates
    /// `sport_type`.
    static func kind(sportType: String?, type: String?) -> ActivityKind {
        let raw = (sportType ?? type ?? "").lowercased()
        switch raw {
        case _ where raw.hasSuffix("run"): return .run
        case _ where raw.hasSuffix("ride"): return .ride
        case _ where raw.hasSuffix("swim"): return .swim
        case _ where raw.hasSuffix("hike"): return .hike
        case _ where raw.hasSuffix("walk"): return .walk
        // `Workout` is deliberately absent: it is Strava's catch-all for
        // mobility, stretching or a class, not a gym session.
        case "weighttraining", "crossfit": return .strength
        default: return .other
        }
    }
}
