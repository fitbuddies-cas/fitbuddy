import Foundation

/// The app's fitness-data sources, built once and shared (#140).
///
/// `ConnectorRegistry` only means something if the connection screen, the
/// sync and the dashboard all look at the same instance — a registry per
/// screen would have each of them see a different connection state. This
/// object is that one instance, plus the Strava and Polar collaborators that
/// have to be shared with it: the credential stores the connectors persist
/// refreshed tokens through, and the OAuth services that carry the browser
/// seam.
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
    let polarCredentialStore = PolarCredentialStore()
    let polarOAuth: PolarOAuthService
    /// Built once `registerConnectors()` has resolved the stable member id
    /// (ADR-11 Nachtrag) — `nil` only in the brief window before that.
    private(set) var polarConnector: PolarConnector?

    init() {
        stravaOAuth = StravaOAuthService(webAuthenticator: WebAuthenticationSession())
        stravaConnector = StravaConnector(oauth: stravaOAuth, credentialStore: stravaCredentialStore)
        polarOAuth = PolarOAuthService(webAuthenticator: WebAuthenticationSession())
    }

    /// Registers every available connector with the registry. Run once at
    /// launch, before anything asks the registry a question — the sync
    /// (#143) fetches every source through it.
    func registerConnectors() async {
        await registry.register(hevyConnector, for: .hevy)
        await registry.register(stravaConnector, for: .strava)

        let memberID = await resolvedPolarMemberID()
        let connector = PolarConnector(
            oauth: polarOAuth,
            credentialStore: polarCredentialStore,
            memberID: memberID
        )
        polarConnector = connector
        await registry.register(connector, for: .polar)
    }

    /// The stable AccessLink `member-id` FitBuddy registers this user under
    /// (ADR-11): whatever is already stored, or a freshly generated one on
    /// the very first launch.
    private func resolvedPolarMemberID() async -> String {
        if let stored = try? await polarCredentialStore.memberID() {
            return stored
        }
        let generated = UUID().uuidString
        try? await polarCredentialStore.saveMemberID(generated)
        return generated
    }
}
