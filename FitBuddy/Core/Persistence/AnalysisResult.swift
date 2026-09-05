import Foundation
import SwiftData

/// One AI recommendation, kept so it survives an app restart and stays
/// readable next to the ones before it (US-3 AC10/AC11, #97/#117).
///
/// SwiftData rather than `UserDefaults`, unlike the rate-limit timestamp next
/// to it: the recommendation text is derived from the user's training data,
/// and only the SwiftData container carries the ADR-001 hardening that health
/// data needs (no CloudKit, no backup, `FileProtectionType.complete`).
///
/// Many rows exist at a time — `AnalysisResultStore.save(...)` appends and
/// keeps the newest 20. The user paid a provider for every one of these texts,
/// so throwing the previous one away with each new run was never the app's
/// call to make.
@Model
final class AnalysisResult {
    /// Identifies the row across actor boundaries, so the history screen can
    /// delete or rate exactly the analysis the user tapped.
    ///
    /// Defaults to a fresh value so an existing store migrates without a
    /// version plan; the single row such a store holds is the only one that
    /// takes the default, and there is nothing for it to collide with.
    var id: UUID = UUID()
    /// The complete recommendation, as the answering provider wrote it.
    var text: String
    /// When the run that produced `text` finished — the basis for the "2 h ago"
    /// line above the recommendation.
    var generatedAt: Date
    /// Length of the window the analysis actually covered, in whole weeks. The
    /// fallback ladder widens it when the last four weeks are empty (#87), so
    /// it has to travel with the text rather than be assumed to be the default.
    var windowWeeks: Int
    /// How many sessions that window held (#36). Stored with the text for the
    /// same reason as `windowWeeks`: the context line above a restored
    /// recommendation has to name the basis of the run that produced it, and
    /// re-counting today's cache would describe a different one.
    ///
    /// Defaults to zero so an existing store migrates without a version plan;
    /// a row written before #36 then reads as thin data, which is the honest
    /// answer for a basis nobody recorded.
    var sessionCount: Int = 0
    /// The user's "Helpful" / "Not helpful" verdict on *this* recommendation,
    /// as `AnalysisFeedback.rawValue`, or `nil` while none was given.
    ///
    /// Here rather than in `UserDefaults` (#117): with a history, a single
    /// stored verdict could no longer be matched to the text it was given for,
    /// and guessing from timestamps put the user's opinion on recommendations
    /// they never rated.
    var feedback: String?

    init(
        id: UUID = UUID(),
        text: String,
        generatedAt: Date,
        windowWeeks: Int,
        sessionCount: Int,
        feedback: String? = nil
    ) {
        self.id = id
        self.text = text
        self.generatedAt = generatedAt
        self.windowWeeks = windowWeeks
        self.sessionCount = sessionCount
        self.feedback = feedback
    }
}
