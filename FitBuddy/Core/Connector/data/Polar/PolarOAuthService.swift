import Foundation
import OSLog

/// Drives Polar's OAuth2 authorization-code flow against the *user's own*
/// Polar API application (ADR-11 Nachtrag, BYO-app — mirrors
/// `StravaOAuthService`):
/// presents the consent page through the shared `WebAuthenticating` seam
/// (#152), validates the callback, and exchanges the code via
/// `PolarOAuthClient`.
///
/// Like `StravaOAuthService` it persists nothing: it takes the user's
/// application credentials on every call, and the caller
/// (`PolarConnectionViewModel`) stores the resulting pair.
///
/// The `state` parameter is a fresh random value per authorization and the
/// callback is rejected if it does not echo it: a custom URL scheme is not
/// exclusive to this app, so the state is what proves the callback answers
/// *our* request.
actor PolarOAuthService: PolarOAuthorizing {
    /// The scheme registered in `Info.plist`; `ASWebAuthenticationSession`
    /// captures the redirect by it.
    static let callbackScheme = "fitbuddy"

    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "PolarOAuthService")

    private let webAuthenticator: any WebAuthenticating
    private let session: URLSession

    /// - Parameters:
    ///   - webAuthenticator: The browser seam. No default on purpose: the real
    ///     `WebAuthenticationSession` is main-actor bound and belongs to the
    ///     composition root.
    ///   - session: Injectable for tests; defaults to the ephemeral
    ///     `.fitBuddy` session so a secret-bearing request never hits disk.
    init(webAuthenticator: any WebAuthenticating, session: URLSession = .fitBuddy) {
        self.webAuthenticator = webAuthenticator
        self.session = session
    }

    // MARK: - PolarOAuthorizing

    func authorize(_ credentials: PolarClientCredentials) async throws -> ConnectorCredentials {
        let client = PolarOAuthClient(credentials: credentials, session: session)
        let state = Self.makeState()

        let authorizationURL = await client.authorizationURL(state: state)
        let callback: URL
        do {
            callback = try await webAuthenticator.authenticate(
                url: authorizationURL,
                callbackURLScheme: Self.callbackScheme
            )
        } catch {
            throw error.isCancellation ? PolarOAuthError.cancelled : PolarOAuthError.transport
        }

        let code = try Self.code(from: callback, expectedState: state)
        return try await client.exchange(code: code)
    }

    func refresh(_ credentials: PolarClientCredentials, refreshToken: String) async throws -> ConnectorCredentials {
        let client = PolarOAuthClient(credentials: credentials, session: session)
        return try await client.refresh(refreshToken: refreshToken)
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

        // Parameter names only — never the code or state values.
        logger.notice(
            "Polar callback: host=\(callback.host ?? "-", privacy: .public) path=\(callback.path, privacy: .public) params=\(items.map(\.name).joined(separator: ","), privacy: .public)"
        )

        guard value("state") == expectedState else {
            logger.error("Polar callback state mismatch (state present: \(value("state") != nil, privacy: .public))")
            throw PolarOAuthError.stateMismatch
        }

        if let error = value("error") {
            logger.error("Polar callback carried error=\(error, privacy: .public) description=\(value("error_description") ?? "-", privacy: .public)")
            throw error == "access_denied" ? PolarOAuthError.accessDenied : PolarOAuthError.invalidCallback
        }

        guard let code = value("code"), !code.isEmpty else {
            logger.error("Polar callback carried neither a code nor an error")
            throw PolarOAuthError.invalidCallback
        }
        return code
    }
}
