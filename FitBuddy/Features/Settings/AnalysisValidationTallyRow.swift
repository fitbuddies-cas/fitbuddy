import Foundation

/// One line of the aggregate in the validation log view (#228): how often the
/// app intervened in one part of the answer for one reason, across the
/// stored analyses.
struct AnalysisValidationTallyRow: Equatable, Identifiable, Sendable {
    let subject: AnalysisInterventionSubject
    let reason: AnalysisInterventionReason
    let count: Int

    var id: String { "\(subject.rawValue).\(reason.rawValue)" }
}
