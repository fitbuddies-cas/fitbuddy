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
    func save(text: String, generatedAt: Date, context: AnalysisContext) throws -> UUID {
        let entry = AnalysisResultSnapshot(
            id: UUID(),
            text: text,
            generatedAt: generatedAt,
            context: context,
            feedback: nil
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

    func setFeedback(_ feedback: AnalysisFeedback?, for id: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        entries[index] = AnalysisResultSnapshot(
            id: entry.id,
            text: entry.text,
            generatedAt: entry.generatedAt,
            context: entry.context,
            feedback: feedback
        )
    }

    func deleteAll() throws {
        entries = []
    }
}
