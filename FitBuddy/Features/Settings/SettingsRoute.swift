import Foundation

/// Screens the settings tab can push, as values (#144).
///
/// Exists so a screen outside the tab can open one of them: the dashboard's
/// «Renew your Strava connection» banner has to land the user on the
/// connection screen (US-5 AC2), and the only way to push onto another tab's
/// `NavigationStack` is through a path the root owns.
enum SettingsRoute: Hashable {
    case strava
    case polar
}
