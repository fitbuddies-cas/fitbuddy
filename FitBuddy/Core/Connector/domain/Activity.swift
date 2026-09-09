import Foundation

/// A training session, normalized across fitness-data providers (ADR-6) so
/// the dashboard and AI analysis read one shape regardless of source.
/// `HevyConnector` (#34) maps Hevy's API responses into this shape; a future
/// `StravaConnector` (#35) does the same for Strava.
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
    var exercises: [ActivityExercise]

    init(
        id: String,
        title: String,
        notes: String? = nil,
        startTime: Date,
        endTime: Date? = nil,
        updatedAt: Date? = nil,
        exercises: [ActivityExercise] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startTime = startTime
        self.endTime = endTime
        self.updatedAt = updatedAt
        self.exercises = exercises
    }
}
