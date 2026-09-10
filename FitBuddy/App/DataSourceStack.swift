import Foundation

/// The app's fitness-data sources, built once and shared (#140).
///
/// `ConnectorRegistry` only means something if the connection screen, the
/// sync and the dashboard all look at the same instance — a registry per
/// screen would have each of them see a different connection state. This
/// object is that one instance, plus the Strava collaborators that have to be
/// shared with it: the credential store the connector persists refreshed
/// tokens through, and the OAuth service that carries the browser seam.
///
/// Main-actor bound because `WebAuthenticationSession` is; it is created here
/// and nowhere else. `RootView` owns one of these as state.
@MainActor
final class DataSourceStack {
    let registry = ConnectorRegistry()
    let stravaCredentialStore = StravaCredentialStore()
    let stravaOAuth: StravaOAuthService
    let stravaConnector: StravaConnector

    init() {
        stravaOAuth = StravaOAuthService(webAuthenticator: WebAuthenticationSession())
        stravaConnector = StravaConnector(oauth: stravaOAuth, credentialStore: stravaCredentialStore)
    }

    /// Registers the connectors with the registry. Run once at launch, before
    /// anything asks the registry a question.
    ///
    /// Hevy is not registered yet: `WorkoutSyncService` still holds its own
    /// `HevyConnector` until #143 moves the sync onto the registry.
    func registerConnectors() async {
        await registry.register(stravaConnector, for: .strava)
    }
}
