import Foundation

/// Credentials a `FitnessConnector` needs to `connect()` (ADR-6). Providers
/// authenticate differently — Hevy with a long-lived API key, a future
/// `StravaConnector` (#35) with an expiring OAuth token — so this is a case
/// per auth scheme rather than one fixed set of fields.
enum ConnectorCredentials: Equatable, Sendable {
    /// A long-lived key sent with every request. Hevy keys do not expire.
    case apiKey(String)
    /// An OAuth 2.0 token pair. `expiresAt` lets the connector's own
    /// `validate()` refresh proactively instead of failing first.
    case oauth(accessToken: String, refreshToken: String, expiresAt: Date)
}
