import Foundation

/// Session-level metrics that an endurance source (Polar, Strava) reports but
/// a strength source (Hevy) does not — heart rate, calories, training load.
///
/// Kept as its own optional type on `Activity` rather than as loose optional
/// fields: a Hevy workout leaves the whole block `nil`, and the dashboard /
/// AI prompt builder can branch on "has cardio metrics?" in one check instead
/// of probing five properties. Every field is optional in turn because even
/// within one Polar exercise the watch may not have recorded, say, distance
/// (indoor session) or training load (strap not worn).
struct ActivityMetrics: Equatable, Codable, Sendable {
    /// Average heart rate over the session, in bpm.
    var averageHeartRate: Int?
    /// Peak heart rate over the session, in bpm.
    var maximumHeartRate: Int?
    /// Active energy expenditure the source attributed to the session, in kcal.
    var activeCalories: Int?
    /// Covered distance, in metres. `nil` for a session the source did not
    /// track spatially (most indoor sessions).
    var distanceMeters: Double?
    /// Wall-clock session duration, in seconds. Redundant with
    /// `Activity.endTime` when that is present, but endurance sources report
    /// the duration directly and often omit an explicit end time.
    var durationSeconds: Int?
    /// Source-computed training load / training impulse for the session. The
    /// scale is provider-specific (Polar's is not Strava's) — treat it as a
    /// trend for one source, never as a cross-source absolute.
    var trainingLoad: Double?
    /// Source's own sport label, verbatim (e.g. `RUNNING`, `CYCLING`). Not
    /// normalised: the AI prompt is happy with the raw term and a fixed enum
    /// would decay to `.other` on every sport the source adds later.
    var sport: String?

    init(
        averageHeartRate: Int? = nil,
        maximumHeartRate: Int? = nil,
        activeCalories: Int? = nil,
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil,
        trainingLoad: Double? = nil,
        sport: String? = nil
    ) {
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.activeCalories = activeCalories
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.trainingLoad = trainingLoad
        self.sport = sport
    }

    /// Whether the block carries at least one recorded value. A Polar exercise
    /// with every field unrecorded maps to `nil`, not to an empty block, so
    /// `Activity.metrics != nil` always means "there is cardio data here".
    var isEmpty: Bool {
        averageHeartRate == nil
            && maximumHeartRate == nil
            && activeCalories == nil
            && distanceMeters == nil
            && durationSeconds == nil
            && trainingLoad == nil
            && sport == nil
    }
}
