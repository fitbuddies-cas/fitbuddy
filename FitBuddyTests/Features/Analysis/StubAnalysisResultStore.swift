import Foundation
@testable import FitBuddy

/// In-memory `AnalysisResultStoring` for the history tests (#117).
///
/// The real store has its own tests against SwiftData; what the history view
/// model needs is a store whose reads and deletes can be made to fail on
/// demand.
actor StubAnalysisResultStore: AnalysisResultStoring {
    enum Failure: Error {
        case unavailable
    }

    private(set) var entries: [AnalysisResultSnapshot]
    /// Set to make `recent(limit:)` throw.
    var readFails = false
    /// Set to make `delete(id:)` throw.
    var deleteFails = false

    init(entries: [AnalysisResultSnapshot] = []) {
        self.entries = entries
    }

    func setReadFails(_ value: Bool) { readFails = value }

    func setDeleteFails(_ value: Bool) { deleteFails = value }

    @discardableResult
    func save(
        text: String,
        report: ValidatedAnalysisReport?,
        provider: LLMProvider?,
        generatedAt: Date,
        context: AnalysisContext,
        confirmation: AnalysisSendConfirmation?
    ) throws -> UUID {
        let entry = AnalysisResultSnapshot(
            id: UUID(),
            text: text,
            generatedAt: generatedAt,
            context: context,
            report: report,
            provider: provider,
            confirmation: confirmation
        )
        entries.append(entry)
        entries.sort { $0.generatedAt > $1.generatedAt }
        return entry.id
    }

    func latest() throws -> AnalysisResultSnapshot? {
        try recent(limit: 1).first
    }

    func recent(limit: Int) throws -> [AnalysisResultSnapshot] {
        if readFails { throw Failure.unavailable }
        return Array(entries.prefix(limit))
    }

    func delete(id: UUID) throws {
        if deleteFails { throw Failure.unavailable }
        entries.removeAll { $0.id == id }
    }

    func deleteAll() throws {
        entries = []
    }
}
