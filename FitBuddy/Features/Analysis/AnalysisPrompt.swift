import Foundation

/// The two halves of one analysis request, as `InferenceService` takes them.
///
/// A value type rather than two loose strings so the system prompt cannot be
/// paired with a user prompt built for a different window.
struct AnalysisPrompt: Equatable, Sendable {
    /// Role, ground rules and the non-medical disclaimer — Claude's `system`.
    let system: String
    /// The user's own training data plus the request — the single user turn.
    let user: String
    /// The rung of the degradation ladder this turn was built at (#187).
    ///
    /// Defaulted, so every call site that builds a prompt by hand — a preview,
    /// a fixture — still describes the untouched prompt. It travels with the
    /// prompt because the report validation has to know which exercises the
    /// model was actually shown: see `AnalysisPromptDetail`.
    var detail: AnalysisPromptDetail = .full
}
