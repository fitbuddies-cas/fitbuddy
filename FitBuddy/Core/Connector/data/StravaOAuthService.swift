import Foundation
import OSLog

/// Strava's OAuth2 authorization-code flow for the user's own API application
/// (ADR-10): the interactive authorization plus the code exchange, and the
/// silent refresh.
///
/// The browser part goes through `WebAuthenticating`; the token endpoint is
/// plain `URLSession`. Both exchanges send the client secret — Strava has no
/// PKCE — which is why the caller passes `StravaClientCredentials` in rather
/// than this service keeping them.
///
/// The `state` parameter is a fresh random value per authorization and the
/// callback is rejected if it does not echo it: with a custom URL scheme any
/// app on the device could in principle open `fitbuddy://oauth/strava`, and
/// the state is what proves the callback answers *our* request.
actor StravaOAuthService: StravaOAuthorizing {
    /// The scheme registered in `Info.plist` and set as "Authorization Callback
    /// Domain" in the user's Strava application.
    static let callbackScheme = "fitbuddy"
    static let redirectURI = "fitbuddy://oauth/strava"
    /// Read access to all activities, private ones included. The only scope
    /// requested — see ADR-10.
    static let scope = "activity:read_all"

    private static let authorizeURL = URL(staticString: "https://www.strava.com/oauth/authorize")
    private static let tokenURL = URL(staticString: "https://www.strava.com/oauth/token")

    private let webAuthenticator: any WebAuthenticating
    private let session: URLSession
    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "StravaOAuth")

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

    // MARK: - StravaOAuthorizing

    func authorize(_ credentials: StravaClientCredentials) async throws -> ConnectorCredentials {
        let state = Self.makeState()
        let callback: URL
        do {
            callback = try await webAuthenticator.authenticate(
                url: Self.authorizeURL(clientID: credentials.clientID, state: state),
                callbackURLScheme: Self.callbackScheme
            )
        } catch {
            throw error.isCancellation ? StravaOAuthError.cancelled : StravaOAuthError.transport
        }

        let code = try Self.code(from: callback, expectedState: state)
        return try await exchange(
            form: [
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
                "grant_type": "authorization_code",
                "code": code,
            ],
            rejectionMeans: .invalidClientCredentials
        )
    }

    func refresh(_ credentials: StravaClientCredentials, refreshToken: String) async throws -> ConnectorCredentials {
        try await exchange(
            form: [
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ],
            rejectionMeans: .invalidGrant
        )
    }

    // MARK: - Authorization

    private static func authorizeURL(clientID: String, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
        ]
        // The components were built from a static, valid URL and simple query
        // items; failing here would be a programming error, not a runtime one.
        return components?.url ?? authorizeURL
    }

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

        guard value("state") == expectedState else { throw StravaOAuthError.stateMismatch }

        if let error = value("error") {
            throw error == "access_denied" ? StravaOAuthError.accessDenied : StravaOAuthError.invalidCallback
        }

        guard let code = value("code"), !code.isEmpty else { throw StravaOAuthError.invalidCallback }

        // Strava echoes the granted scopes comma-separated, e.g.
        // "read,activity:read_all". The user can untick ours on the consent page.
        let granted = value("scope")?.split(separator: ",").map(String.init) ?? []
        guard granted.contains(scope) else { throw StravaOAuthError.missingScope }

        return code
    }

    // MARK: - Token endpoint

    /// Posts `form` to the token endpoint and decodes the pair.
    ///
    /// - Parameter rejectionMeans: What a 400/401 means when Strava's error body
    ///   does not name the client credentials. During the code exchange the code
    ///   was issued seconds ago, so a rejection almost certainly blames the
    ///   secret; during a refresh the far likelier cause is a revoked or
    ///   already-rotated refresh token.
    private func exchange(form: [String: String], rejectionMeans: StravaOAuthError) async throws -> ConnectorCredentials {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody(form)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error.isCancellation { throw StravaOAuthError.cancelled }
            throw StravaOAuthError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw StravaOAuthError.transport }

        switch http.statusCode {
        case 200...299:
            guard let dto = try? JSONDecoder().decode(StravaTokenDTO.self, from: data) else {
                logger.error("Token endpoint returned \(http.statusCode, privacy: .public) with an undecodable body")
                throw StravaOAuthError.invalidResponse
            }
            return dto.makeCredentials()
        case 400, 401:
            let body = try? JSONDecoder().decode(StravaOAuthErrorDTO.self, from: data)
            throw body?.blamesClientCredentials == true ? .invalidClientCredentials : rejectionMeans
        default:
            logger.error("Token endpoint returned unexpected status \(http.statusCode, privacy: .public)")
            throw StravaOAuthError.unexpectedStatus(http.statusCode)
        }
    }

    /// `application/x-www-form-urlencoded`, keys sorted so the body is
    /// deterministic.
    ///
    /// Encoded by hand rather than via `URLComponents.percentEncodedQuery`,
    /// which leaves `+` alone — and a `+` in a form body reads as a space on
    /// the server. Only unreserved characters (RFC 3986 §2.3) pass through.
    private static func formBody(_ form: [String: String]) -> Data {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        func encode(_ raw: String) -> String {
            raw.addingPercentEncoding(withAllowedCharacters: unreserved) ?? raw
        }
        let pairs = form.keys.sorted().map { "\(encode($0))=\(encode(form[$0] ?? ""))" }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
