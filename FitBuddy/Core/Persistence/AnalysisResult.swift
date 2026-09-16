import Foundation
import SwiftData

/// The current `AnalysisResult` model — see `FitBuddySchemaV3`.
typealias AnalysisResult = FitBuddySchemaV3.AnalysisResult

extension FitBuddySchemaV3 {
    /// One AI recommendation, kept so it survives an app restart and stays
    /// readable next to the ones before it (US-3 AC10/AC11, #97/#117).
    ///
    /// SwiftData rather than `UserDefaults`: the recommendation text is derived from the user's training
    /// data, and only the SwiftData container carries the ADR-001 hardening
    /// that health data needs (no CloudKit, no backup,
    /// `FileProtectionType.complete`).
    ///
    /// Many rows exist at a time — `AnalysisResultStore.save(...)` appends and
    /// keeps the newest 20. The user paid a provider for every one of these
    /// texts, so throwing the previous one away with each new run was never
    /// the app's call to make.
    @Model
    final class AnalysisResult {
        /// Identifies the row across actor boundaries, so the history screen
        /// can delete exactly the analysis the user tapped.
        ///
        /// Defaults to a fresh value so an existing store migrates without a
        /// version plan; the single row such a store holds is the only one
        /// that takes the default, and there is nothing for it to collide with.
        var id: UUID = UUID()
        /// The complete recommendation as prose — the answering provider's text,
        /// or a report's `summary`. Always set: it is what an old row renders,
        /// and the fallback whenever `reportJSON` cannot be read.
        var text: String
        /// When the run that produced `text` finished — the basis for the
        /// "2 h ago" line above the recommendation.
        var generatedAt: Date
        /// Length of the window the analysis actually covered, in whole weeks.
        /// The fallback ladder widens it when the last four weeks are empty
        /// (#87), so it has to travel with the text rather than be assumed to
        /// be the default.
        var windowWeeks: Int
        /// How many sessions that window held (#36). Stored with the text for
        /// the same reason as `windowWeeks`: the context line above a restored
        /// recommendation has to name the basis of the run that produced it,
        /// and re-counting today's cache would describe a different one.
        ///
        /// Defaults to zero so an existing store migrates without a version
        /// plan; a row written before #36 then reads as thin data, which is
        /// the honest answer for a basis nobody recorded.
        var sessionCount: Int = 0
        /// The `ValidatedAnalysisReport` the user saw, JSON-encoded (US-14
        /// AC6, #176) — `nil` for a prose answer and for every row written
        /// before V3. The validated report rather than the model's raw one, so
        /// the history shows the same cards, with the app's recovery figures
        /// as of that run, and not a re-validation against today's cache.
        ///
        /// Read it through `AnalysisResultSnapshot.report`, never directly:
        /// what the bytes mean depends on `reportVersion`.
        var reportJSON: Data?
        /// The format of `reportJSON` — see `AnalysisReportFormat`. 0 means
        /// prose (no report), which is what the V2 → V3 stage fills existing
        /// rows with.
        var reportVersion: Int = 0
        /// `LLMProvider.rawValue` of the provider that wrote this answer — the
        /// last one of the fallback chain (#176), read it through `provider`.
        /// `nil` on rows written before V3, which did not record it.
        var providerRawValue: String?
        /// Unused: held the "Helpful" / "Not helpful" verdict until those
        /// buttons were removed. Dropping it would be a lightweight change of
        /// its own; #176 left it out to keep V3 purely additive.
        var feedback: String?

        /// Typed view of `providerRawValue`. An unknown raw value — a store
        /// written by a newer build — reads as `nil`, so the badge falls back
        /// to a bare "AI" rather than naming a provider on a guess.
        var provider: LLMProvider? {
            providerRawValue.flatMap(LLMProvider.init(rawValue:))
        }

        init(
            id: UUID = UUID(),
            text: String,
            generatedAt: Date,
            windowWeeks: Int,
            sessionCount: Int,
            reportJSON: Data? = nil,
            reportVersion: Int = AnalysisReportFormat.prose,
            providerRawValue: String? = nil
        ) {
            self.id = id
            self.text = text
            self.generatedAt = generatedAt
            self.windowWeeks = windowWeeks
            self.sessionCount = sessionCount
            self.reportJSON = reportJSON
            self.reportVersion = reportVersion
            self.providerRawValue = providerRawValue
        }
    }
}
