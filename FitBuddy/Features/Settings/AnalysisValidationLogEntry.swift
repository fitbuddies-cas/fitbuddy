import Foundation

// Developer tooling: excluded from Release builds, so the validation log
// view never ships in a TestFlight binary. The log itself is captured and
// stored in every build (#228).
#if DEBUG

/// One stored analysis as the validation log view lists it (#228).
struct AnalysisValidationLogEntry: Equatable, Identifiable, Sendable {
    /// The stored analysis's identity.
    let id: UUID
    let generatedAt: Date
    let log: AnalysisValidationLog
}

#endif
