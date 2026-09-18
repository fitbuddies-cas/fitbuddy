import Foundation

/// UI state of the on-demand AI analysis (US-3, #31).
///
/// One value carries the whole screen, so no combination of flags can describe
/// a state the analysis cannot actually be in — "running and failed" is not
/// representable. Every path out of `running` ends in `result`, `error` or
/// `idle`, which is what keeps the button from getting stuck (#31 AC1).
enum AnalysisState: Equatable {
    /// Nothing requested yet, or the last run was cancelled — the analysis
    /// button is the only thing on screen.
    case idle
    /// A run is in flight: the spinner phase (US-3 AC1), from the tap until
    /// the answer is complete. Carries no text on purpose — the answer is a
    /// JSON report that only means something once it is whole, so nothing of
    /// it is shown before then (#178).
    case running
    /// The run finished. Carries the complete answer, in one step.
    case result(AnalysisOutcome)
    /// The run failed.
    case error(AnalysisFailure)

    /// Whether a call is currently in flight — the state in which starting
    /// another analysis must be impossible.
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// The finished answer, or `nil` in every state that carries none.
    var outcome: AnalysisOutcome? {
        guard case .result(let outcome) = self else { return nil }
        return outcome
    }
}
