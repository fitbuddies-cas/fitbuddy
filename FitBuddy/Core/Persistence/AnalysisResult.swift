import Foundation
import SwiftData

/// The current `AnalysisResult` model — see `FitBuddySchemaV3`.
typealias AnalysisResult = FitBuddySchemaV3.AnalysisResult

extension FitBuddySchemaV3 {
    /// One AI recommendation, kept so it survives an app restart and stays
    /// readable next to the ones before it (US-3 AC10/AC11, #97/#117).
    ///
    /// SwiftData rather than `UserDefaults`, unlike the rate-limit timestamp
    /// next to it: the recommendation text is derived from the user's training
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
        /// The complete recommendation, as the answering provider wrote it.
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
        /// Unused: held the "Helpful" / "Not helpful" verdict until those
        /// buttons were removed. Kept so installed stores open without a
        /// migration — nothing writes it since, and V3 kept it rather than
        /// spending a migration stage on a column nobody reads (#202 makes
        /// the same call, so the two V3s stay mergeable).
        var feedback: String?

        init(
            id: UUID = UUID(),
            text: String,
            generatedAt: Date,
            windowWeeks: Int,
            sessionCount: Int,
            goal: String? = nil,
            experience: String? = nil
        ) {
            self.id = id
            self.text = text
            self.generatedAt = generatedAt
            self.windowWeeks = windowWeeks
            self.sessionCount = sessionCount
            self.goal = goal
            self.experience = experience
        }
    }
}
