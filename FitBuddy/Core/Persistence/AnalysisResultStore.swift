import Foundation
import SwiftData

/// Owns the single persisted AI recommendation (US-3 AC10, #97).
///
/// A `@ModelActor` for the same reason as `WorkoutStore`: a `ModelContext` is
/// not `Sendable`, so every write is serialized here rather than happening on
/// the `@MainActor`, and only value types leave this actor.
@ModelActor
actor AnalysisResultStore {
    /// Replaces the stored recommendation with this one.
    ///
    /// Delete and insert share one `save()`, so a failing write leaves the
    /// previous recommendation intact rather than none at all.
    func save(text: String, generatedAt: Date, context: AnalysisContext) throws {
        try deleteStoredResults()
        modelContext.insert(
            AnalysisResult(
                text: text,
                generatedAt: generatedAt,
                windowWeeks: context.window.weeks,
                sessionCount: context.sessionCount
            )
        )
        try saveOrRollback()
    }

    /// The stored recommendation, or `nil` when none was ever completed.
    ///
    /// Newest first, and only the first row is read: `save(...)` keeps exactly
    /// one, but a store written by a future build that keeps a history must
    /// still restore the latest rather than an arbitrary row.
    func latest() throws -> AnalysisResultSnapshot? {
        var descriptor = FetchDescriptor<AnalysisResult>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let result = try modelContext.fetch(descriptor).first else { return nil }
        return AnalysisResultSnapshot(
            text: result.text,
            generatedAt: result.generatedAt,
            context: AnalysisContext(
                sessionCount: result.sessionCount,
                window: AnalysisWindow(weeks: result.windowWeeks)
            )
        )
    }

    /// Drops the stored recommendation (hard logout, replaced Hevy key,
    /// "delete all data").
    func deleteAll() throws {
        try deleteStoredResults()
        try saveOrRollback()
    }

    /// Deletes every stored recommendation without saving.
    ///
    /// A failing fetch must propagate: swallowing it would let `save(...)`
    /// insert a second row on top of the old one, and `latest()` would then
    /// keep restoring whichever of the two sorts first.
    private func deleteStoredResults() throws {
        for result in try modelContext.fetch(FetchDescriptor<AnalysisResult>()) {
            modelContext.delete(result)
        }
    }

    /// Saves, discarding the pending changes if the save fails — without the
    /// rollback the failed delete and insert would stay in this actor's
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
