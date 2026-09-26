import Foundation

/// One stored analysis as the validation log view lists it (#228).
struct AnalysisValidationLogEntry: Equatable, Identifiable, Sendable {
    /// The stored analysis's identity.
    let id: UUID
    let generatedAt: Date
    let log: AnalysisValidationLog
}
