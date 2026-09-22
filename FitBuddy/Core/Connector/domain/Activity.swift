import Foundation

/// A training session, normalized across fitness-data providers (ADR-6) so
/// the dashboard and AI analysis read one shape regardless of source.
/// `HevyConnector` (#34) maps Hevy's API responses into this shape;
/// `StravaConnector` (#142, ADR-10) and `PolarConnector` (ADR-11) do the same
/// for Strava activities and Polar endurance sessions respectively.
struct Activity: Identifiable, Equatable, Codable, Sendable {
    /// The source provider's own identifier (e.g. Hevy's workout id), so a
    /// re-sync can be matched against what is already cached.
    let id: String
    var title: String
    /// Free text the user wrote about the session as a whole (Hevy's
    /// `description`, Strava's `description`); `nil` when none was logged.
    var notes: String?
    var startTime: Date
    var endTime: Date?
    /// When the source last modified the activity, when it reports it. Kept
    /// for the delta sync planned on top of `/workouts/events`.
    var updatedAt: Date?
    /// The provider this activity came from (#141). With two sources side by
    /// side, the cache needs it to replace one source's window without
    /// dropping the other's, and the dashboard needs it to say which is which.
    var source: ConnectorSource
    /// What kind of training this was (#180) — the normalized sport, so the
    /// prompt builder and the cards do not have to read it out of the title.
    var kind: ActivityKind
    var exercises: [ActivityExercise]
    /// Session-level endurance metrics (heart rate, elevation, speed, effort)
    /// when the source provides them. `nil` for a strength source like Hevy;
    /// set for a Strava activity (ADR-10) or a Polar exercise (ADR-11).
    /// Additive — the dashboard stays valid without reading it.
    var cardio: CardioMetrics?

    /// - Parameter source: Defaults to Hevy, the only source before #141, so
    ///   the mapping and every fixture written against it stay valid. The
    ///   default is the initializer's only: the synthesized `Codable` still
    ///   requires the `source` key, so JSON without it does not decode —
    ///   nothing decodes `Activity` from JSON today, and a fixture that does
    ///   has to carry the key.
    /// - Parameter kind: Defaults to strength, which is what every Hevy
    ///   workout is and what the model held implicitly before #180.
    init(
        id: String,
        title: String,
        notes: String? = nil,
        startTime: Date,
        endTime: Date? = nil,
        updatedAt: Date? = nil,
        source: ConnectorSource = .hevy,
        kind: ActivityKind = .strength,
        exercises: [ActivityExercise] = [],
        cardio: CardioMetrics? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startTime = startTime
        self.endTime = endTime
        self.updatedAt = updatedAt
        self.source = source
        self.kind = kind
        self.exercises = exercises
        self.cardio = cardio
    }
}
