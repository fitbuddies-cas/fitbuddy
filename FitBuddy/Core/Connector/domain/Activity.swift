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
    var startTime: Date
    var endTime: Date?
    var exercises: [ActivityExercise]

    init(
        id: String,
        title: String,
        startTime: Date,
        endTime: Date? = nil,
        exercises: [ActivityExercise] = []
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.exercises = exercises
    }
}
