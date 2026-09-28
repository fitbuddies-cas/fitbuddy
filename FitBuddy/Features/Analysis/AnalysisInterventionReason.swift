import Foundation

/// Why the validator intervened in part of the model's answer (#228) — a
/// typed reason, never free text, so the rate of each can be counted over
/// several runs (#229).
///
/// The card reasons mirror the checks of `AnalysisReportValidator` one to
/// one; the progression ones are `AnalysisReportValidator.ProgressionRejection`
/// under the same names. The report-level reasons name what the app changed
/// around the cards.
enum AnalysisInterventionReason: String, Codable, CaseIterable, Equatable, Sendable {
    // MARK: Any card

    /// The card carried no reasoning, or a note no text.
    case blankText
    /// The card belongs to a domain the analysis profile left out (US-15
    /// AC5): a load under "Endurance", an interference card under a
    /// single-domain profile.
    case domainNotCovered

    // MARK: Load and rep progression (#175, #233, #234)

    case notListed
    case noWorkingWeight
    case wrongStartingWeight
    case wrongStartingReps
    case noIncrease
    case conditionNotMet
    case conditionNotCheckable
    case noLoadStep
    case belowRange
    case aboveRange
    case offStep
    case aboveRepStep

    // MARK: Recovery and interference

    /// A recovery card in a week the app's own count does not call for rest.
    case recoveryNotNeeded
    /// An interference card in a week without both domains in it.
    case noInterference

    // MARK: Imbalance

    /// A group that is no `MuscleGroup`, `.other`, or both groups the same.
    case unknownMuscleGroup
    /// A per-week figure that is not the app's.
    case frequencyMismatch
    /// The app's two figures are equal — no imbalance to state.
    case noImbalance

    // MARK: Metric (#186)

    /// The card has no label to title it with.
    case missingLabel
    /// A unit the model may not set a target in, e.g. a heart rate.
    case unitNotStatable
    /// The app has no figure in that unit for the last seven days.
    case noAppFigure
    /// `from` is not the app's figure.
    case wrongStartingFigure
    /// `to` is the app's figure, or further from it than `metricStepShare`.
    case stepOutOfRange
    /// A figure the unit cannot state, or a step that rounds to nothing.
    case unreadableFigure

    // MARK: Report level

    /// The week calls for recovery and the model sent no recovery card
    /// (US-14 AC4): the app inserted one.
    case recoveryMissing
    /// The app's verdict is `insufficientData`, and the card stated one
    /// anyway (ADR-014 §6).
    case noVerdict
    /// Past `AnalysisReportValidator.maxCards`.
    case overCardLimit
    /// The app's verdict differs from the model's (ADR-014 §7) — on the
    /// verdict itself, and on the headline and lead that argued for it.
    case verdictOverridden
    /// A progress lead over a report where no surviving card backs a step
    /// (#170).
    case noBackingCard

    /// The reason of a rejected progression check.
    init(_ rejection: AnalysisReportValidator.ProgressionRejection) {
        switch rejection {
        case .notListed: self = .notListed
        case .noWorkingWeight: self = .noWorkingWeight
        case .wrongStartingWeight: self = .wrongStartingWeight
        case .wrongStartingReps: self = .wrongStartingReps
        case .noIncrease: self = .noIncrease
        case .conditionNotMet: self = .conditionNotMet
        case .conditionNotCheckable: self = .conditionNotCheckable
        case .noLoadStep: self = .noLoadStep
        case .belowRange: self = .belowRange
        case .aboveRange: self = .aboveRange
        case .offStep: self = .offStep
        case .aboveRepStep: self = .aboveRepStep
        }
    }
}
