import Foundation

/// What the analysis tab can push onto its own `NavigationStack` (#117).
///
/// An enum rather than a `NavigationLink` with an inline destination: the
/// history screen builds a view model, and `navigationDestination` is the one
/// place that construction happens once per push instead of once per render.
enum AnalysisRoute: Hashable {
    /// The list of stored analyses (US-3 AC11).
    case history
}
