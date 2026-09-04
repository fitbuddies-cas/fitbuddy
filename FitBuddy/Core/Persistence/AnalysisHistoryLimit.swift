import Foundation

/// How many AI recommendations FitBuddy keeps (US-3 AC11, #117).
///
/// Its own type rather than a constant on `AnalysisResultStore`: the store
/// trims to it and the history screen reads to it, and the screen otherwise
/// knows nothing about the concrete store — only about
/// `AnalysisResultStoring`.
///
/// Twenty rather than everything: the history is there to look a few weeks
/// back, not to be an archive, and a prose recommendation the user never
/// scrolls to is still health-derived data sitting on the device.
enum AnalysisHistoryLimit {
    static let rows = 20
}
