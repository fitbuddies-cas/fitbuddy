import Foundation

/// A stored recommendation reduced to `Sendable` values (#97).
///
/// `AnalysisResultStore` hands these out instead of `AnalysisResult`, for the
/// same reason `WorkoutStore` returns `WorkoutSummary`: a `@Model` instance is
/// bound to its `ModelContext` and must not cross an actor boundary.
struct AnalysisResultSnapshot: Equatable, Sendable, Identifiable {
    /// The stored row's identity — what the history screen deletes by (#117).
    let id: UUID
    let text: String
    let generatedAt: Date
    /// What the recommendation rests on, rebuilt from the stored week count
    /// and session count so the restored screen names the basis exactly as the
    /// live run did (#87, #36).
    let context: AnalysisContext
}
