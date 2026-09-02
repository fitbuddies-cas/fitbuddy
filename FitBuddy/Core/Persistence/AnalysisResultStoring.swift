import Foundation

/// Read/write access to the persisted AI recommendation (#97).
///
/// `AnalysisViewModel` depends on this protocol rather than on
/// `AnalysisResultStore`, so a preview can drive the analysis screen without a
/// `ModelContainer` and a test can observe what was persisted.
protocol AnalysisResultStoring: Sendable {
    func save(text: String, generatedAt: Date, window: AnalysisWindow) async throws
    func latest() async throws -> AnalysisResultSnapshot?
    func deleteAll() async throws
}

extension AnalysisResultStore: AnalysisResultStoring {}
