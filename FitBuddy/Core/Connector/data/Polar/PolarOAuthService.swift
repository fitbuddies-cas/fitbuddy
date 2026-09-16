import Foundation

/// Drives the interactive half of Polar's OAuth2 + PKCE flow (ADR-11, #156):
/// presents the consent page through the shared `WebAuthenticating` seam
/// (#152), validates the callback, exchanges the code via `PolarOAuthClient`,
/// and — on success — persists the resulting pair through
/// `PolarCredentialStoring` before handing it back to the caller.
///
/// Persisting here rather than in the connection ViewModel (Strava's split)
/// is deliberate: Polar has no client-secret screen and no per-user
/// application, so there is nothing left for the ViewModel to own besides
/// starting the flow and reading the result back out of the store.
///
/// The `state` parameter is a fresh random value per authorization and the
/// callback is rejected if it does not echo it, for the same reason
/// `StravaOAuthService` checks it: a custom URL scheme is not exclusive to
/// this app, so the state is what proves the callback answers *our* request.
actor PolarOAuthService: PolarOAuthorizing {
    private let client: PolarOAuthClient
    private let webAuthenticator: any WebAuthenticating
    private let credentialStore: any PolarCredentialStoring
    private let callbackScheme: String

    /// - Parameters:
    ///   - configuration: Supplies the authorization URL and the redirect URI
    ///     whose scheme `ASWebAuthenticationSession` watches for.
    ///   - webAuthenticator: The browser seam. No default on purpose: the real
    ///     `WebAuthenticationSession` is main-actor bound and belongs to the
    ///     composition root.
    ///   - credentialStore: Where the pair lands on success.
    ///   - session: Injectable for tests; defaults to the ephemeral
    ///     `.fitBuddy` session so a token-bearing request never hits disk.
    init(
        configuration: PolarClientConfiguration,
        webAuthenticator: any WebAuthenticating,
        credentialStore: any PolarCredentialStoring,
        session: URLSession = .fitBuddy
    ) {
        self.client = PolarOAuthClient(configuration: configuration, session: session)
        self.webAuthenticator = webAuthenticator
        self.credentialStore = credentialStore
        // `ASWebAuthenticationSession` matches purely on scheme, so the host
        // and path of the redirect URI ("fitbuddy://polar/callback") do not
        // matter here — only "fitbuddy" does.
        self.callbackScheme = URL(string: configuration.redirectURI)?.scheme ?? "fitbuddy"
    }

    // MARK: - PolarOAuthorizing

    func authorize() async throws -> ConnectorCredentials {
        let pkce = PolarPKCE()
        let state = Self.makeState()

        let authorizationURL = await client.authorizationURL(pkce: pkce, state: state)
        let callback: URL
        do {
            callback = try await webAuthenticator.authenticate(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            )
        } catch {
            throw error.isCancellation ? PolarOAuthError.cancelled : error
        }

        let code = try Self.code(from: callback, expectedState: state)
        let pair = try await client.exchange(code: code, pkce: pkce)

        guard case .oauth(let accessToken, let refreshToken, let expiresAt) = pair else {
            throw ConnectorError.invalidResponse
        }
        try await credentialStore.saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        return pair
    }

    // MARK: - Callback validation

    /// 32 random bytes, hex-encoded: unguessable and safe in a query string.
    private static func makeState() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    /// Validates the callback and extracts the authorization code.
    ///
    /// Order matters: the state is checked before anything else, because a
    /// callback with the wrong state is not ours and nothing in it — not even
    /// its `error` — should be believed.
    private static func code(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard value("state") == expectedState else { throw PolarOAuthError.stateMismatch }

        if let error = value("error") {
            throw error == "access_denied" ? PolarOAuthError.accessDenied : PolarOAuthError.invalidCallback
        }

        guard let code = value("code"), !code.isEmpty else { throw PolarOAuthError.invalidCallback }
        return code
    }
}
