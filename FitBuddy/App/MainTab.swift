/// The three top-level areas behind the bottom tab bar (#107).
///
/// Lives outside `MainTabView` so `RootView` can drive the selection: the
/// dashboard's CTA jumps to the analysis tab, and a fall-back into onboarding
/// puts the next start on the dashboard again.
enum MainTab: Hashable {
    case dashboard
    case analysis
    case settings
}
