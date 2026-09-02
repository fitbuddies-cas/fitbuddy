import Foundation

/// The stored recommendation reduced to `Sendable` values (#97).
///
/// `AnalysisResultStore` hands these out instead of `AnalysisResult`, for the
/// same reason `WorkoutStore` returns `WorkoutSummary`: a `@Model` instance is
/// bound to its `ModelContext` and must not cross an actor boundary.
struct AnalysisResultSnapshot: Equatable, Sendable {
    let text: String
    let generatedAt: Date
    /// The window the recommendation covers, rebuilt from the stored week
    /// count so the restored screen names it exactly as the live run did (#87).
    let window: AnalysisWindow
}
