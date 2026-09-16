import Foundation
import OSLog

/// Drives Polar's OAuth2 authorization-code token plumbing (ADR-11):
/// builds the authorization URL, exchanges the returned code for tokens, and
/// refreshes an expired access token — all against the *user's* own Polar
/// application credentials (`PolarClientCredentials`), never a team default.
///
/// The interactive part — presenting the authorization URL and catching the
/// redirect — belongs to `PolarOAuthService`; this actor is only the token
/// plumbing, so it stays unit-testable with a stub `URLSession` and carries no
/// UI dependency.
///
/// Every request authenticates with HTTP Basic `clientID:clientSecret`. No
/// PKCE: AccessLink v3's authorization endpoint documents no
/// `code_challenge`/`code_challenge_method` parameter.
actor PolarOAuthClient {
    private let credentials: PolarClientCredentials
    private let session: URLSession
    private let now: () -> Date
    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "PolarOAuthClient")

    init(
        credentials: PolarClientCredentials,
        session: URLSession = .fitBuddy,
        now: @escaping () -> Date = Date.init
    ) {
        self.credentials = credentials
        self.session = session
        self.now = now
    }

    /// URL to load in `ASWebAuthenticationSession`. `state` is opaque and must
    /// be compared against the value on the redirect to defend against a
    /// forged callback.
    func authorizationURL(state: String) -> URL {
        var components = URLComponents(
            url: PolarClientConfiguration.authorizationURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: PolarClientConfiguration.redirectURI),
            URLQueryItem(name: "scope", value: PolarClientConfiguration.scope),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components?.url else {
            preconditionFailure("Malformed Polar authorization URL")
        }
        return url
    }

    /// Exchanges an authorization `code` for an access/refresh token pair.
    func exchange(code: String) async throws -> ConnectorCredentials {
        let fields = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": PolarClientConfiguration.redirectURI,
        ]
        let response = try await postToken(fields)
        return response.credentials(now: now(), previousRefresh: nil)
    }

    /// Trades a refresh token for a fresh access token. A `400`/`401` here
    /// means the refresh token itself is dead → `.unauthorized`, and the
    /// caller must restart the consent flow.
    func refresh(refreshToken: String) async throws -> ConnectorCredentials {
        let fields = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        let response = try await postToken(fields)
        return response.credentials(now: now(), previousRefresh: refreshToken)
    }

    // MARK: - Token endpoint

    private func postToken(_ fields: [String: String]) async throws -> PolarTokenResponse {
        var request = URLRequest(url: PolarClientConfiguration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let raw = "\(credentials.clientID):\(credentials.clientSecret)"
        let encoded = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.httpBody = Self.formBody(fields)

        let (data, http) = try await PolarHTTP.send(request, on: session)
        guard (200...299).contains(http.statusCode) else {
            // The body is logged too: Polar's OAuth errors (RFC 6749 §5.2,
            // e.g. `invalid_scope`, `invalid_client`, `unauthorized_client`)
            // explain exactly what's wrong and never contain the secret.
            let body = String(decoding: data, as: UTF8.self)
            logger.error("Token endpoint returned \(http.statusCode, privacy: .public): \(body, privacy: .public)")
            throw PolarHTTP.failure(for: http)
        }
        do {
            return try JSONDecoder().decode(PolarTokenResponse.self, from: data)
        } catch {
            logger.error("Token response could not be decoded: \(error, privacy: .public)")
            throw ConnectorError.invalidResponse
        }
    }

    /// `application/x-www-form-urlencoded` body with each value percent-encoded
    /// for the query-item character set (so `/` and `+` in a token survive).
    static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }
}
