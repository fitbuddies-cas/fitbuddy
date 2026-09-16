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
/// and nowhere else. `RootView` owns one as a `@StateObject` — the one
/// property wrapper whose initial value is an autoclosure, so the stack is
/// built once rather than on every re-creation of the view struct. It
/// publishes nothing; the conformance is only what `@StateObject` asks for.
@MainActor
final class DataSourceStack: ObservableObject {
    let registry = ConnectorRegistry()
    let hevyConnector = HevyConnector()
    let stravaCredentialStore = StravaCredentialStore()
    let stravaOAuth: StravaOAuthService
    let stravaConnector: StravaConnector

    init() {
        stravaOAuth = StravaOAuthService(webAuthenticator: WebAuthenticationSession())
        stravaConnector = StravaConnector(oauth: stravaOAuth, credentialStore: stravaCredentialStore)
    }

    /// Registers both connectors with the registry. Run once at launch,
    /// before anything asks the registry a question — the sync (#143) fetches
    /// every source through it.
    func registerConnectors() async {
        await registry.register(hevyConnector, for: .hevy)
        await registry.register(stravaConnector, for: .strava)
    }
}
