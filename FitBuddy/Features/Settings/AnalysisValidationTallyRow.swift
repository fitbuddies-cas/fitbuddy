import Foundation

// Developer tooling: excluded from Release builds, so the validation log
// view never ships in a TestFlight binary. The log itself is captured and
// stored in every build (#228).
#if DEBUG

/// One line of the aggregate in the validation log view (#228): how often the
/// app intervened in one part of the answer for one reason, across the
/// stored analyses.
struct AnalysisValidationTallyRow: Equatable, Identifiable, Sendable {
    let subject: AnalysisInterventionSubject
    let reason: AnalysisInterventionReason
    let count: Int

    var id: String { "\(subject.rawValue).\(reason.rawValue)" }
}

#endif
