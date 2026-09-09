import Foundation

/// What the dashboard tab can push onto its own `NavigationStack` besides a
/// tapped session (#37).
///
/// An enum rather than a `NavigationLink` with an inline destination, for the
/// reason `AnalysisRoute` is one: the exercise list builds a view model, and
/// `navigationDestination` is the one place that construction happens once per
/// push instead of once per render.
enum DashboardRoute: Hashable {
    /// The searchable list of all exercises in the window (US-7).
    case exercises
}
