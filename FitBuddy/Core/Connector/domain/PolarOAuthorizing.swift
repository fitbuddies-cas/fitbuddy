import Foundation

/// The two OAuth operations Polar needs (ADR-11, mirrors
/// `StravaOAuthorizing`): the interactive authorization that yields the first
/// token pair, and the silent refresh `PolarConnector` runs when the access
/// token is about to expire.
///
/// Both take the user's application credentials on every call rather than
/// holding them — Polar requires the client secret for the refresh grant too
/// (HTTP Basic auth on every token-endpoint request), and the caller (not
/// this service) owns where the secret is stored.
protocol PolarOAuthorizing: Sendable {
    /// Runs the browser flow and exchanges the resulting code. Throws
    /// `PolarOAuthError` for a failure in the interactive part, or
    /// `ConnectorError` for one at the token endpoint.
    func authorize(_ credentials: PolarClientCredentials) async throws -> ConnectorCredentials

    /// Exchanges `refreshToken` for a new pair. Throws `ConnectorError`.
    func refresh(_ credentials: PolarClientCredentials, refreshToken: String) async throws -> ConnectorCredentials
}
