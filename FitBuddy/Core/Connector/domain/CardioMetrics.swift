import Foundation

/// Session-level endurance metrics that Strava and Polar report but a strength
/// source (Hevy) does not — heart rate, elevation, speed, energy, effort
/// (#180).
///
/// Kept as its own optional block on `Activity` rather than as loose optional
/// fields: a Hevy workout leaves the whole thing `nil`, so the prompt builder
/// and the cards branch on "is there cardio data?" once instead of probing ten
/// properties. Every field is optional in turn because what a session carries
/// depends on the provider, the sport and the gear: an indoor ride has no
/// elevation, a run without a strap has no heart rate, and only Polar reports
/// a training load.
///
/// Replaces the Polar-only `ActivityMetrics` of #158. Two overlapping metric
/// blocks on one `Activity` — both carrying heart rate — would have made
/// "which one does the prompt read?" a per-source question.
///
/// Scales are provider-specific where the comments say so; treat those as a
/// trend within one source, never as a cross-source absolute.
///
/// `Hashable` rather than only `Equatable`: `WorkoutSummary` carries the block
/// and is pushed as a `NavigationLink` value, which requires the whole summary
/// to hash.
struct CardioMetrics: Codable, Hashable, Sendable {
    /// Average heart rate over the session, in bpm.
    var averageHeartRate: Int?
    /// Peak heart rate over the session, in bpm.
    var maxHeartRate: Int?
    /// Cumulative ascent, in metres (Strava's `total_elevation_gain`).
    var elevationGainMeters: Double?
    /// Average speed, in metres per second — the form both Strava reports and
    /// `PaceFormatter` consumes, so nothing converts on the way in or out.
    var averageSpeedMetersPerSecond: Double?
    /// Mechanical work the source attributed to the session, in kilojoules
    /// (Strava's `kilojoules`, power-meter rides only). Not a calorie count:
    /// `activeCalories` is the metabolic figure.
    var energyKilojoules: Double?
    /// Strava's Relative Effort (`suffer_score`): an objective score Strava
    /// derives from heart rate against the athlete's own zones, with an
    /// undisclosed formula. `nil` when the session recorded no heart rate.
    ///
    /// **Not a self-assessment.** It is not an RPE and not "perceived" in any
    /// sense — Strava's user-entered rating is `perceived_exertion`, which is
    /// not decoded. The scale is source-specific: never compare it with, or
    /// average it into, a Hevy RPE or a Polar load; read it only as a trend
    /// within Strava (ADR-015, #242). Named `perceivedEffort` until #243.
    var relativeEffort: Double?
    /// Active energy expenditure the source attributed to the session, in
    /// kcal (Polar's `calories`).
    var activeCalories: Int?
    /// Covered distance in metres, for a source that reports it at session
    /// level and logs no sets (Polar). A Strava or Hevy session carries its
    /// distance on `ActivityExerciseSet` instead, where the dashboard already
    /// aggregates it — filling both would double-count it.
    var distanceMeters: Double?
    /// Session duration in seconds, for the same source as `distanceMeters`
    /// and for the same reason.
    var durationSeconds: Int?
    /// Source-computed training load / training impulse (Polar's legacy
    /// `training_load`, the only load older devices report).
    /// Provider-specific scale.
    var trainingLoad: Double?
    /// Polar's cardio load for the session (`training_load_pro.cardio-load`,
    /// #244): a TRIMP on Polar's own calibration, objective and heart-rate
    /// based. Only devices with Training Load Pro report it.
    /// Provider-specific scale — a trend within Polar, never compared with
    /// Strava's `relativeEffort` (ADR-015, #242).
    var cardioLoad: Double?
    /// Polar's muscle load (`training_load_pro.muscle-load`): the mechanical
    /// load of the session, from a power meter. Provider-specific scale.
    var muscleLoad: Double?
    /// Polar's perceived load (`training_load_pro.perceived-load`): the
    /// user's own rating weighted by duration, so subjective. Polar keeps it
    /// apart from `cardioLoad` on purpose, and so does the app — never merged
    /// into one number with it or with any other source's value.
    var perceivedLoad: Double?
    /// The rating of perceived exertion the user gave the session on the
    /// watch or in Polar Flow (`training_load_pro.user-rpe`). Polar's own
    /// label, not a number — see `PolarUserRPE`.
    var userRPE: PolarUserRPE?

    init(
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        elevationGainMeters: Double? = nil,
        averageSpeedMetersPerSecond: Double? = nil,
        energyKilojoules: Double? = nil,
        relativeEffort: Double? = nil,
        activeCalories: Int? = nil,
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil,
        trainingLoad: Double? = nil,
        cardioLoad: Double? = nil,
        muscleLoad: Double? = nil,
        perceivedLoad: Double? = nil,
        userRPE: PolarUserRPE? = nil
    ) {
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.elevationGainMeters = elevationGainMeters
        self.averageSpeedMetersPerSecond = averageSpeedMetersPerSecond
        self.energyKilojoules = energyKilojoules
        self.relativeEffort = relativeEffort
        self.activeCalories = activeCalories
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.trainingLoad = trainingLoad
        self.cardioLoad = cardioLoad
        self.muscleLoad = muscleLoad
        self.perceivedLoad = perceivedLoad
        self.userRPE = userRPE
    }

    /// Whether the block carries at least one recorded value. A session with
    /// every field unrecorded maps to `nil`, not to an empty block, so
    /// `Activity.cardio != nil` always means "there is cardio data here".
    var isEmpty: Bool {
        averageHeartRate == nil
            && maxHeartRate == nil
            && elevationGainMeters == nil
            && averageSpeedMetersPerSecond == nil
            && energyKilojoules == nil
            && relativeEffort == nil
            && activeCalories == nil
            && distanceMeters == nil
            && durationSeconds == nil
            && trainingLoad == nil
            && cardioLoad == nil
            && muscleLoad == nil
            && perceivedLoad == nil
            && userRPE == nil
    }

    /// The block itself, or `nil` when nothing was recorded.
    var nonEmpty: CardioMetrics? {
        isEmpty ? nil : self
    }
}
