import Foundation
import SwiftData

/// Owns the persisted AI recommendations (US-3 AC10/AC11, #97/#117).
///
/// A `@ModelActor` for the same reason as `WorkoutStore`: a `ModelContext` is
/// not `Sendable`, so every write is serialized here rather than happening on
/// the `@MainActor`, and only value types leave this actor.
@ModelActor
actor AnalysisResultStore {
    /// How many recommendations are kept. Everything past this is dropped on
    /// the next save, newest kept.
    ///
    /// Twenty rather than everything: the history is there to look a few weeks
    /// back, not to be an archive, and a prose recommendation the user never
    /// scrolls to is still health-derived data sitting on the device.
    static let historyLimit = 20

    /// Appends a finished recommendation and returns its identity.
    ///
    /// Insert and trim share one `save()`, so a failing write leaves the
    /// history exactly as it was rather than half-pruned.
    @discardableResult
    func save(text: String, generatedAt: Date, context: AnalysisContext) throws -> UUID {
        let result = AnalysisResult(
            text: text,
            generatedAt: generatedAt,
            windowWeeks: context.window.weeks,
            sessionCount: context.sessionCount
        )
        modelContext.insert(result)
        try trimToLimit()
        try saveOrRollback()
        return result.id
    }

    /// The newest recommendation, or `nil` when none was ever completed.
    func latest() throws -> AnalysisResultSnapshot? {
        try recent(limit: 1).first
    }

    /// The newest `limit` recommendations, newest first — the history list
    /// (US-3 AC11).
    func recent(limit: Int) throws -> [AnalysisResultSnapshot] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<AnalysisResult>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(Self.snapshot(of:))
    }

    /// Removes exactly one recommendation — the swipe on a history row.
    ///
    /// A row that is already gone is not an error: two screens can hold the
    /// same list, and the second delete has nothing left to do.
    func delete(id: UUID) throws {
        guard let result = try result(with: id) else { return }
        modelContext.delete(result)
        try saveOrRollback()
    }

    /// Records the user's verdict on one recommendation (US-3 AC9), or clears
    /// it with `nil`.
    func setFeedback(_ feedback: AnalysisFeedback?, for id: UUID) throws {
        guard let result = try result(with: id) else { return }
        result.feedback = feedback?.rawValue
        try saveOrRollback()
    }

    /// Drops the whole history (hard logout, replaced Hevy key, "delete all
    /// data").
    func deleteAll() throws {
        for result in try modelContext.fetch(FetchDescriptor<AnalysisResult>()) {
            modelContext.delete(result)
        }
        try saveOrRollback()
    }

    // MARK: - Helpers

    private func result(with id: UUID) throws -> AnalysisResult? {
        var descriptor = FetchDescriptor<AnalysisResult>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Deletes everything past `historyLimit`, newest kept, without saving.
    ///
    /// The surplus is taken with `dropFirst` rather than with the descriptor's
    /// `fetchOffset`: on a context holding the freshly inserted row, that
    /// offset does not narrow the result, and the fetch comes back with every
    /// row — which this loop would then delete, the new one included.
    ///
    /// A failing fetch must propagate: swallowing it would let the store grow
    /// past the limit unnoticed, and the one thing this cap protects is how
    /// much health-derived text the device keeps.
    private func trimToLimit() throws {
        let descriptor = FetchDescriptor<AnalysisResult>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        let stored = try modelContext.fetch(descriptor)
        guard stored.count > Self.historyLimit else { return }
        for surplus in stored.dropFirst(Self.historyLimit) {
            modelContext.delete(surplus)
        }
    }

    private static func snapshot(of result: AnalysisResult) -> AnalysisResultSnapshot {
        AnalysisResultSnapshot(
            id: result.id,
            text: result.text,
            generatedAt: result.generatedAt,
            context: AnalysisContext(
                sessionCount: result.sessionCount,
                window: AnalysisWindow(weeks: result.windowWeeks)
            ),
            feedback: result.feedback.flatMap(AnalysisFeedback.init(rawValue:))
        )
    }

    /// Saves, discarding the pending changes if the save fails — without the
    /// rollback the failed insert and deletes would stay in this actor's
    /// context and be committed by the next successful save.
    private func saveOrRollback() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
