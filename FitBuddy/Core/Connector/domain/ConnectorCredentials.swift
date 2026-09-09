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

    /// When these credentials stop working, or `nil` for a scheme that does
    /// not expire. `ConnectorRegistry` records it on `connect` — it is the
    /// only place the expiry is visible without asking the provider.
    var expiresAt: Date? {
        switch self {
        case .apiKey:
            return nil
        case .oauth(_, _, let expiresAt):
            return expiresAt
        }
    }
}
