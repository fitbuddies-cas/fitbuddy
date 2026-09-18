import Foundation
@testable import FitBuddy

/// Test double for the two per-exercise reads the analysis prompt makes
/// (#173), so `AnalysisViewModel` can be driven without a SwiftData container.
///
/// Calls arrive from the ViewModel's `@MainActor` context, so the mutable
/// state below is only ever touched from one actor — hence `@unchecked`.
final class StubAnalysisExerciseCache: ExerciseSummaryReading, ExerciseProgressionReading, @unchecked Sendable {
    /// Returned by `exerciseSummaries(since:)`.
    var exercises: [ExerciseSummary] = []
    /// Returned by `exerciseProgression(id:since:)`, keyed by movement id.
    var progressions: [String: ExerciseProgression] = [:]
    /// When set, the summary read throws.
    var error: Error?

    /// The `since` argument of the last summary read.
    private(set) var requestedSummariesSince: Date?
    /// Every movement id a progression was read for, in call order.
    private(set) var requestedProgressionIDs: [String] = []
    /// The `since` argument of the last progression read.
    private(set) var requestedProgressionSince: Date?

    func exerciseSummaries(since date: Date) async throws -> [ExerciseSummary] {
        requestedSummariesSince = date
        if let error { throw error }
        return exercises
    }

    func exerciseProgression(id: String, since date: Date) async throws -> ExerciseProgression? {
        requestedProgressionIDs.append(id)
        requestedProgressionSince = date
        return progressions[id]
    }

    struct Failure: Error {}
}
