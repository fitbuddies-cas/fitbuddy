import Foundation

/// One place where the app did not take the model's answer as sent (US-16
/// AC4, #228): which part, what the app did to it, why, and — where the
/// check compared figures — the model's figure next to the app's.
///
/// Recorded by `AnalysisReportValidator` while it validates, collected in an
/// `AnalysisValidationLog`.
struct AnalysisIntervention: Codable, Equatable, Sendable {
    let subject: AnalysisInterventionSubject
    let action: AnalysisInterventionAction
    let reason: AnalysisInterventionReason
    let figure: AnalysisInterventionFigure?

    init(
        subject: AnalysisInterventionSubject,
        action: AnalysisInterventionAction,
        reason: AnalysisInterventionReason,
        figure: AnalysisInterventionFigure? = nil
    ) {
        self.subject = subject
        self.action = action
        self.reason = reason
        self.figure = figure
    }
}
