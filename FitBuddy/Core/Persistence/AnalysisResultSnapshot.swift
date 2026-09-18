import Foundation

/// A stored recommendation reduced to `Sendable` values (#97).
///
/// `AnalysisResultStore` hands these out instead of `AnalysisResult`, for the
/// same reason `WorkoutStore` returns `WorkoutSummary`: a `@Model` instance is
/// bound to its `ModelContext` and must not cross an actor boundary.
struct AnalysisResultSnapshot: Equatable, Sendable, Identifiable {
    /// The stored row's identity — what the history screen deletes by (#117).
    let id: UUID
    /// The recommendation as prose. Always present: it is what renders when
    /// `report` is `nil`.
    let text: String
    let generatedAt: Date
    /// What the recommendation rests on, rebuilt from the stored week count
    /// and session count so the restored screen names the basis exactly as the
    /// live run did (#87, #36).
    let context: AnalysisContext
    /// The cards the user saw (US-14 AC6, #176), decoded when the snapshot is
    /// built. `nil` for a prose answer, for a row written before V4, and for a
    /// report this build cannot read — in each case `text` renders instead.
    let report: ValidatedAnalysisReport?
    /// The provider that wrote the answer (#176), or `nil` when the row did
    /// not record one — the badge then stays a bare "AI".
    let provider: LLMProvider?

    init(
        id: UUID,
        text: String,
        generatedAt: Date,
        context: AnalysisContext,
        report: ValidatedAnalysisReport? = nil,
        provider: LLMProvider? = nil
    ) {
        self.id = id
        self.text = text
        self.generatedAt = generatedAt
        self.context = context
        self.report = report
        self.provider = provider
    }
}
