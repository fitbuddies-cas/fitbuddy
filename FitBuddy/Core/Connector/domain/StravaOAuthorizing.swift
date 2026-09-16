import Foundation

/// The two OAuth operations Strava needs (ADR-10): the interactive
/// authorization that yields the first token pair, and the silent refresh the
/// connector runs when the access token is about to expire.
///
/// Both take the user's application credentials on every call rather than
/// holding them — Strava requires the client secret for the refresh grant too,
/// and the caller (not this service) owns where the secret is stored.
protocol StravaOAuthorizing: Sendable {
    /// Runs the browser flow and exchanges the resulting code. Throws
    /// `StravaOAuthError`.
    func authorize(_ credentials: StravaClientCredentials) async throws -> ConnectorCredentials

    /// Exchanges `refreshToken` for a new pair. The refresh token in the
    /// result replaces the one passed in — Strava rotates it. Throws
    /// `StravaOAuthError`.
    func refresh(_ credentials: StravaClientCredentials, refreshToken: String) async throws -> ConnectorCredentials
}
