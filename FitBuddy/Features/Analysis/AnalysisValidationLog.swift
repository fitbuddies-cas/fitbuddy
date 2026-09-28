import Foundation

/// What the app did not take from one model answer as sent (US-16 AC4, #228),
/// stored with the analysis so the hit rate over several runs is measurable
/// (#229).
///
/// Built by `AnalysisReportValidator` while it validates; the provider and
/// model are added by the caller that knows which one answered
/// (`attributed(to:)`), because the validator only sees the answer.
///
/// **No health data beyond what the measurement needs.** The model's verdict
/// and figures and the app's reason are kept; the model's reasoning, the
/// exercise titles and the session data are not.
struct AnalysisValidationLog: Codable, Equatable, Sendable {
    /// The provider that wrote the answer — the last one of the fallback
    /// chain. `nil` until `attributed(to:)`.
    var provider: LLMProvider?
    /// The model that provider was asked with, e.g. `claude-opus-5`.
    var model: String?
    /// What the model chose (ADR-014 §7).
    let modelVerdict: AnalysisVerdict
    /// What the app derived from its own figures and showed (#227).
    let appVerdict: AnalysisVerdict
    /// The stage of `AnalysisVerdictRule` that produced `appVerdict`.
    let verdictReason: AnalysisVerdictRule.Reason
    /// Every intervention, in the order the validator made them. Empty when
    /// the answer went through as sent.
    let interventions: [AnalysisIntervention]

    init(
        provider: LLMProvider? = nil,
        model: String? = nil,
        modelVerdict: AnalysisVerdict,
        appVerdict: AnalysisVerdict,
        verdictReason: AnalysisVerdictRule.Reason,
        interventions: [AnalysisIntervention]
    ) {
        self.provider = provider
        self.model = model
        self.modelVerdict = modelVerdict
        self.appVerdict = appVerdict
        self.verdictReason = verdictReason
        self.interventions = interventions
    }

    /// Whether the app overruled the model's verdict.
    var verdictOverridden: Bool {
        modelVerdict != appVerdict
    }

    /// This log with the provider that answered, and the model the app asks
    /// that provider with.
    func attributed(to provider: LLMProvider?) -> AnalysisValidationLog {
        var copy = self
        copy.provider = provider
        copy.model = provider?.analysisModel
        return copy
    }
}
