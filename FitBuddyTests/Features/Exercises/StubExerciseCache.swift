import Foundation
@testable import FitBuddy

/// In-memory `ExerciseSummaryReading` for the exercise-list tests (#37).
///
/// An actor because the protocol is `Sendable` and the tests read what the
/// view model asked for after the fact.
actor StubExerciseCache: ExerciseSummaryReading {
    struct Failure: Error {}

    var exercises: [ExerciseSummary] = []
    var error: Error?
    /// The window boundary the view model passed in, for the clock test.
    private(set) var requestedDate: Date?

    func setExercises(_ exercises: [ExerciseSummary]) {
        self.exercises = exercises
    }

    func setError(_ error: Error?) {
        self.error = error
    }

    func exerciseSummaries(since date: Date) async throws -> [ExerciseSummary] {
        requestedDate = date
        if let error { throw error }
        return exercises
    }
}
