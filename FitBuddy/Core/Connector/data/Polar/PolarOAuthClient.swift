import Foundation
import OSLog

/// Drives the Polar OAuth2 authorization-code + PKCE flow (ADR-11): builds the
/// authorization URL, exchanges the returned code for tokens, and refreshes an
/// expired access token.
///
/// The interactive part — presenting `authorizationURL` and catching the
/// redirect — belongs to a ViewModel with `ASWebAuthenticationSession`; this
/// actor is only the token plumbing, so it stays unit-testable with a stub
/// `URLSession` and carries no UI dependency.
actor PolarOAuthClient {
    private let configuration: PolarClientConfiguration
    private let session: URLSession
    private let now: () -> Date
    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "PolarOAuthClient")

    init(
        configuration: PolarClientConfiguration,
        session: URLSession = .fitBuddy,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.session = session
        self.now = now
    }

    /// URL to load in `ASWebAuthenticationSession`. `state` is opaque and must
    /// be compared against the value on the redirect to defend against a
    /// forged callback.
    func authorizationURL(pkce: PolarPKCE, state: String) -> URL {
        var components = URLComponents(
            url: configuration.authorizationURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: "accesslink.read_all"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]
        guard let url = components?.url else {
            preconditionFailure("Malformed Polar authorization URL from \(configuration.authorizationURL)")
        }
        return url
    }

    /// Exchanges an authorization `code` for an access/refresh token pair.
    func exchange(code: String, pkce: PolarPKCE) async throws -> ConnectorCredentials {
        var fields = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": configuration.redirectURI,
            "code_verifier": pkce.verifier,
        ]
        // A public client identifies itself in the body; a confidential one via
        // HTTP Basic (added in `tokenRequest`).
        if configuration.clientSecret == nil {
            fields["client_id"] = configuration.clientID
        }
        let response = try await postToken(fields)
        return response.credentials(now: now(), previousRefresh: nil)
    }

    /// Trades a refresh token for a fresh access token. A `400`/`401` here
    /// means the refresh token itself is dead → `.unauthorized`, and the
    /// caller must restart the consent flow.
    func refresh(refreshToken: String) async throws -> ConnectorCredentials {
        var fields = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        if configuration.clientSecret == nil {
            fields["client_id"] = configuration.clientID
        }
        let response = try await postToken(fields)
        return response.credentials(now: now(), previousRefresh: refreshToken)
    }

    // MARK: - Token endpoint

    private func postToken(_ fields: [String: String]) async throws -> PolarTokenResponse {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let secret = configuration.clientSecret {
            let raw = "\(configuration.clientID):\(secret)"
            let encoded = Data(raw.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = Self.formBody(fields)

        let (data, http) = try await PolarHTTP.send(request, on: session)
        guard (200...299).contains(http.statusCode) else {
            logger.error("Token endpoint returned \(http.statusCode, privacy: .public)")
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
