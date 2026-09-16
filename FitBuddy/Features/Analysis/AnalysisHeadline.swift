import Foundation

/// The verdict headline at the top of a report (US-14 AC1, #177).
///
/// Derived from the verdict rather than taken from the model's `headline`:
/// the verdict is an enum the validator can overrule (US-14 AC4), the sentence
/// is free text that could still say "progress" after the app turned the
/// report into a recovery week.
enum AnalysisHeadline {
    /// The headline split where design 3.4/3.5 breaks it: `["You're ready",
    /// "to progress."]`.
    static func lines(for verdict: AnalysisVerdict) -> [String] {
        switch verdict {
        case .progress: return ["You're ready", "to progress."]
        case .recover: return ["Recover", "this week."]
        // Not in the mock: the same two-line rhythm as the recovery headline.
        case .hold: return ["Hold steady", "this week."]
        }
    }

    /// The headline as one sentence — what VoiceOver reads.
    static func text(for verdict: AnalysisVerdict) -> String {
        lines(for: verdict).joined(separator: " ")
    }
}
