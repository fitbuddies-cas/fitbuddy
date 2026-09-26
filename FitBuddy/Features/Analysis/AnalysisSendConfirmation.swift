import Foundation

/// The proof that the user confirmed one transfer of their training data
/// before it happened (US-3 AC12, #268): when they ticked the box, which
/// consent text was current, and which providers the sheet listed as the
/// recipients — in the fallback order they were shown.
///
/// Built by `AnalysisSendConfirmationViewModel.confirm()` and stored with the
/// recommendation the run produced, so the history can say "Confirmed on …
/// · sent to …" for every row. A row without one predates the sheet.
///
/// The provider list is the one the user saw, not the one that answered:
/// `AnalysisAttribution` records who was actually tried. The two can differ —
/// a key removed between the tap and the call — and only the shown list is
/// what the confirmation covered.
struct AnalysisSendConfirmation: Equatable, Sendable {
    /// When the user tapped "Send & analyze".
    let confirmedAt: Date
    /// `ConsentViewModel.currentVersion` at that moment — the onboarding
    /// consent this per-run confirmation sits on top of.
    let consentVersion: String
    /// The recipients as listed on the sheet: every provider with a stored
    /// key, in fallback order. Empty when no key was stored — the run then
    /// fails before anything is sent, and the row is never written.
    let providers: [LLMProvider]

    init(confirmedAt: Date, consentVersion: String, providers: [LLMProvider]) {
        self.confirmedAt = confirmedAt
        self.consentVersion = consentVersion
        self.providers = providers
    }
}
