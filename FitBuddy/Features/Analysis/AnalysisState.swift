import Foundation

/// UI state of the on-demand AI analysis (US-3, #31).
///
/// One value carries the whole screen, so no combination of flags can describe
/// a state the analysis cannot actually be in — "streaming and failed" is not
/// representable. Every path out of `loading` and `streaming` ends in
/// `result`, `error` or `idle`, which is what keeps the button from getting
/// stuck (#31 AC1).
enum AnalysisState: Equatable {
    /// Nothing requested yet, or the last run was cancelled — the analysis
    /// button is the only thing on screen.
    case idle
    /// The request is on its way and no provider has sent a first token yet:
    /// the spinner phase (US-3 AC1). Also re-entered mid-run when the chain
    /// falls back and the next provider starts from nothing (#79).
    case loading
    /// Text is arriving. Carries everything received so far, so the view can
    /// render the answer as it grows.
    case streaming(String)
    /// The stream finished. Carries the complete recommendation.
    case result(String)
    /// The run failed before or during streaming.
    case error(AnalysisFailure)

    /// Whether a call is currently in flight — the two states in which
    /// starting another analysis must be impossible.
    var isRunning: Bool {
        switch self {
        case .loading, .streaming:
            return true
        case .idle, .result, .error:
            return false
        }
    }

    /// The text received so far, in the two states that carry any.
    var text: String? {
        switch self {
        case .streaming(let text), .result(let text):
            return text
        case .idle, .loading, .error:
            return nil
        }
    }
}
