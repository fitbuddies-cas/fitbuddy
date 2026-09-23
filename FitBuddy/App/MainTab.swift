/// The four top-level areas behind the bottom tab bar (#107, #264).
///
/// Lives outside `MainTabView` so `RootView` can drive the selection: a
/// fall-back into onboarding puts the next start on the dashboard again.
enum MainTab: Hashable {
    case dashboard
    /// The searchable exercise list and, behind it, the progression curves
    /// (US-7, US-9). Its own tab since #264 — a toolbar button on the
    /// dashboard was too easy to miss.
    case exercises
    case analysis
    case settings
}
