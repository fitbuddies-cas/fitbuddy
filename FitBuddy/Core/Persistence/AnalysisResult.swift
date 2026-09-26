import Foundation
import SwiftData

/// The current `AnalysisResult` model — see `FitBuddySchemaV7`.
typealias AnalysisResult = FitBuddySchemaV7.AnalysisResult

extension FitBuddySchemaV7 {
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
        /// How those sessions split across the sources, JSON-encoded (US-15
        /// AC4, #182) — read it through `SessionCountFormat`, never directly.
        ///
        /// Stored next to `sessionCount` rather than replacing it: the total is
        /// what every row since #36 carries, and it is what a row whose map
        /// this build cannot read falls back to. `nil` on every row written
        /// before #182, where it means "all of them Hevy's" and not "none" —
        /// the analysis had no other source to count.
        var sessionCountsJSON: Data?
        /// The analysis profile the run was made under, as
        /// `AnalysisProfile.rawValue` (US-15 AC1, #185) — `nil` on every row
        /// written before the choice existed, where it means "there was none"
        /// and not "Overall load".
        ///
        /// Stored because the profile decided which domains reached the
        /// prompt: without it two rows from the same week can give opposite
        /// advice with nothing in the history to explain why. Its own column
        /// rather than a key in `sessionCountsJSON`: that blob describes the
        /// sessions, and this is a decision about them.
        var analysisProfileRawValue: String?
        /// The training goal the run was steered by, as `TrainingGoal.rawValue`
        /// (US-13 AC4, #192) — `nil` when the user had not set one. Stored for
        /// the same reason as `sessionCount`: the basis line above a restored
        /// recommendation has to name what that run saw, and a goal changed in
        /// Settings since would describe a different one. Optional, filled
        /// with `nil` by the V2 → V3 stage: rows written before #192 read as
        /// "no profile", which is what those runs had.
        var goal: String?
        /// The strength training experience the run was steered by, as
        /// `TrainingExperience.rawValue` — see `goal`.
        var experience: String?
        /// The `ValidatedAnalysisReport` the user saw, JSON-encoded (US-14
        /// AC6, #176) — `nil` for a prose answer and for every row written
        /// before V4. The validated report rather than the model's raw one, so
        /// the history shows the same cards, with the app's recovery figures
        /// as of that run, and not a re-validation against today's cache.
        ///
        /// Read it through `AnalysisResultSnapshot.report`, never directly:
        /// what the bytes mean depends on `reportVersion`.
        var reportJSON: Data?
        /// The format of `reportJSON` — see `AnalysisReportFormat`. 0 means
        /// prose (no report), which is what the V3 → V4 stage fills existing
        /// rows with.
        var reportVersion: Int = 0
        /// `LLMProvider.rawValue` of the provider that wrote this answer — the
        /// last one of the fallback chain (#176), read it through `provider`.
        /// `nil` on rows written before V4, which did not record it.
        var providerRawValue: String?
        /// What the validator rejected, downgraded or overrode in the model's
        /// answer, JSON-encoded (US-16 AC4, #228) — read it through
        /// `AnalysisValidationLogFormat`, never directly.
        ///
        /// A blob next to the row rather than a table of its own, the way
        /// `sessionCountsJSON` is: the log only means anything together with
        /// the analysis it describes, is deleted with it, and its reasons grow
        /// with the validator without a schema version per reason. `nil` on a
        /// prose answer and on every row written before V7 — "not recorded",
        /// not "nothing rejected".
        var validationLogJSON: Data?
        /// Unused: held the "Helpful" / "Not helpful" verdict until those
        /// buttons were removed. Kept so installed stores open without a
        /// migration — nothing writes it since, and neither V3 nor V4 spent a
        /// migration stage on a column nobody reads; both stay purely additive.
        var feedback: String?

        /// Typed view of `providerRawValue`. An unknown raw value — a store
        /// written by a newer build — reads as `nil`, so the badge falls back
        /// to a bare "AI" rather than naming a provider on a guess.
        var provider: LLMProvider? {
            providerRawValue.flatMap(LLMProvider.init(rawValue:))
        }

        /// Typed view of `analysisProfileRawValue`, with the same reading of an
        /// unknown value as `provider`: a profile a newer build wrote is
        /// nothing this one can name, so the row renders without one rather
        /// than claiming a guess.
        var analysisProfile: AnalysisProfile? {
            analysisProfileRawValue.flatMap(AnalysisProfile.init(rawValue:))
        }

        init(
            id: UUID = UUID(),
            text: String,
            generatedAt: Date,
            windowWeeks: Int,
            sessionCount: Int,
            sessionCountsJSON: Data? = nil,
            analysisProfileRawValue: String? = nil,
            goal: String? = nil,
            experience: String? = nil,
            reportJSON: Data? = nil,
            reportVersion: Int = AnalysisReportFormat.prose,
            providerRawValue: String? = nil,
            validationLogJSON: Data? = nil
        ) {
            self.id = id
            self.text = text
            self.generatedAt = generatedAt
            self.windowWeeks = windowWeeks
            self.sessionCount = sessionCount
            self.sessionCountsJSON = sessionCountsJSON
            self.analysisProfileRawValue = analysisProfileRawValue
            self.goal = goal
            self.experience = experience
            self.reportJSON = reportJSON
            self.reportVersion = reportVersion
            self.providerRawValue = providerRawValue
            self.validationLogJSON = validationLogJSON
        }
    }
}
