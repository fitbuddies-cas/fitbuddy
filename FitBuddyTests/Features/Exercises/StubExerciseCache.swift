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
    /// While set, every read suspends until `releaseReads()` — for the tests
    /// that look at the state *during* a read (#264).
    private(set) var holdsReads = false
    private var heldReads: [CheckedContinuation<Void, Never>] = []
    /// How many reads are currently waiting on `releaseReads()`.
    var heldReadCount: Int { heldReads.count }

    func setExercises(_ exercises: [ExerciseSummary]) {
        self.exercises = exercises
    }

    func setError(_ error: Error?) {
        self.error = error
    }

    func setHoldsReads(_ holdsReads: Bool) {
        self.holdsReads = holdsReads
    }

    /// Lets every held read continue with the cache's current contents.
    func releaseReads() {
        let held = heldReads
        heldReads = []
        held.forEach { $0.resume() }
    }

    func exerciseSummaries(since date: Date) async throws -> [ExerciseSummary] {
        requestedDate = date
        if holdsReads {
            await withCheckedContinuation { heldReads.append($0) }
        }
        if let error { throw error }
        return exercises
    }
}
