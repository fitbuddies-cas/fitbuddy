import Foundation
import SwiftData

/// Owns the persisted AI recommendations (US-3 AC10/AC11, #97/#117).
///
/// A `@ModelActor` for the same reason as `WorkoutStore`: a `ModelContext` is
/// not `Sendable`, so every write is serialized here rather than happening on
/// the `@MainActor`, and only value types leave this actor.
@ModelActor
actor AnalysisResultStore {
    /// Appends a finished recommendation and returns its identity.
    ///
    /// `text` is stored whether or not a `report` comes with it: it is what
    /// renders when the report cannot be read back (US-14 AC6, #176).
    /// `provider` is the one that wrote the answer — the last of the fallback
    /// chain.
    ///
    /// Insert and trim share one `save()`, so a failing write leaves the
    /// history exactly as it was rather than half-pruned.
    @discardableResult
    func save(
        text: String,
        report: ValidatedAnalysisReport? = nil,
        provider: LLMProvider? = nil,
        generatedAt: Date,
        context: AnalysisContext
    ) throws -> UUID {
        let encoded = AnalysisReportFormat.encode(report)
        let result = AnalysisResult(
            text: text,
            generatedAt: generatedAt,
            windowWeeks: context.window.weeks,
            sessionCount: context.sessionCount,
            sessionCountsJSON: SessionCountFormat.encode(context),
            analysisProfileRawValue: context.analysisProfile?.rawValue,
            goal: context.profile.goal?.rawValue,
            experience: context.profile.experience?.rawValue,
            reportJSON: encoded.json,
            reportVersion: encoded.version,
            providerRawValue: provider?.rawValue
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

    /// Deletes everything past `AnalysisHistoryLimit.rows`, newest kept,
    /// without saving.
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
        guard stored.count > AnalysisHistoryLimit.rows else { return }
        for surplus in stored.dropFirst(AnalysisHistoryLimit.rows) {
            modelContext.delete(surplus)
        }
    }

    /// Decodes the report here, once per row, so everything past the store
    /// deals in a typed `report` or none — never in bytes and versions. A
    /// report that does not decode leaves the row readable as prose rather
    /// than failing the whole read (US-14 AC6).
    private static func snapshot(of result: AnalysisResult) -> AnalysisResultSnapshot {
        AnalysisResultSnapshot(
            id: result.id,
            text: result.text,
            generatedAt: result.generatedAt,
            context: context(of: result),
            report: AnalysisReportFormat.decode(result.reportJSON, version: result.reportVersion),
            provider: result.provider
        )
    }

    /// The data basis of a stored row (#36, #87, #182, #185).
    ///
    /// A row without a domain breakdown takes the initializer that derives one
    /// from the sources — that is what a run counted before #182 meant — and a
    /// row whose breakdown could not be read keeps its bare total. Making all
    /// three readings explicit here keeps them apart.
    private static func context(of result: AnalysisResult) -> AnalysisContext {
        // `flatMap` rather than a crash on a value this build no longer knows:
        // a goal renamed in a later version leaves the row readable, minus that
        // one line.
        let profile = TrainingProfile(
            goal: result.goal.flatMap(TrainingGoal.init(rawValue:)),
            experience: result.experience.flatMap(TrainingExperience.init(rawValue:))
        )
        let window = AnalysisWindow(weeks: result.windowWeeks)
        let analysisProfile = result.analysisProfile
        switch SessionCountFormat.decode(
            result.sessionCountsJSON,
            fallbackSessionCount: result.sessionCount
        ) {
        case .unattributed(let total):
            return AnalysisContext(
                unattributedSessionCount: total,
                window: window,
                analysisProfile: analysisProfile,
                profile: profile
            )
        case .breakdown(let sources, let domains, let analysed):
            guard let domains else {
                return AnalysisContext(
                    sessionCounts: sources,
                    window: window,
                    analysisProfile: analysisProfile,
                    profile: profile
                )
            }
            return AnalysisContext(
                sessionCounts: sources,
                domainCounts: domains,
                analysedCounts: analysed,
                window: window,
                analysisProfile: analysisProfile,
                profile: profile
            )
        }
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
