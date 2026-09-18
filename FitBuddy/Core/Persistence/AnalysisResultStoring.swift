import Foundation

/// Read/write access to the persisted AI recommendations (#97, #117).
///
/// `AnalysisViewModel` and `AnalysisHistoryViewModel` depend on this protocol
/// rather than on `AnalysisResultStore`, so a preview can drive the analysis
/// screen without a `ModelContainer` and a test can observe what was persisted.
protocol AnalysisResultStoring: Sendable {
    /// Stores a finished recommendation and returns its identity, so the
    /// caller can recognise exactly this row later.
    ///
    /// `text` is always the prose fallback; `report` is the validated report
    /// the user saw, if any, and `provider` the one that wrote the answer
    /// (#176).
    @discardableResult
    func save(
        text: String,
        report: ValidatedAnalysisReport?,
        provider: LLMProvider?,
        generatedAt: Date,
        context: AnalysisContext
    ) async throws -> UUID
    func latest() async throws -> AnalysisResultSnapshot?
    /// The newest `limit` recommendations, newest first.
    func recent(limit: Int) async throws -> [AnalysisResultSnapshot]
    func delete(id: UUID) async throws
    func deleteAll() async throws
}

extension AnalysisResultStore: AnalysisResultStoring {}
