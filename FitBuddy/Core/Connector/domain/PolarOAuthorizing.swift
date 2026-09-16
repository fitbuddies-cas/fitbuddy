import Foundation

/// The interactive Polar OAuth operation (ADR-11): the browser-based
/// authorization-code + PKCE flow that yields the first token pair.
///
/// Unlike `StravaOAuthorizing`, there is no `refresh` here — Polar's silent
/// refresh needs no browser and no PKCE state, so `PolarConnector` calls
/// `PolarOAuthClient.refresh` directly (see its `freshAccessToken()`).
protocol PolarOAuthorizing: Sendable {
    /// Runs the browser flow, exchanges the resulting code, and persists the
    /// pair via the credential store. Throws `PolarOAuthError` for a failure
    /// in the interactive part, or `ConnectorError` for one at the token
    /// endpoint.
    func authorize() async throws -> ConnectorCredentials
}
