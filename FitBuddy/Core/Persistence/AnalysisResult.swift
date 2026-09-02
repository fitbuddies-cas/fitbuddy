import Foundation
import SwiftData

/// The last AI recommendation, kept so it survives an app restart (US-3 AC10,
/// #97).
///
/// SwiftData rather than `UserDefaults`, unlike the cooldown timestamp and the
/// feedback verdict next to it: the recommendation text is derived from the
/// user's training data, and only the SwiftData container carries the ADR-001
/// hardening that health data needs (no CloudKit, no backup,
/// `FileProtectionType.complete`).
///
/// Exactly one row exists at a time — `AnalysisResultStore.save(...)` replaces
/// it. A history of past analyses is deliberately out of scope for v0: the 6h
/// cooldown allows one analysis per window anyway, and no user story asks for
/// a list.
@Model
final class AnalysisResult {
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

    init(text: String, generatedAt: Date, windowWeeks: Int, sessionCount: Int) {
        self.text = text
        self.generatedAt = generatedAt
        self.windowWeeks = windowWeeks
        self.sessionCount = sessionCount
    }
}
