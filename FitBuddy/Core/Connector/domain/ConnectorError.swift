import Foundation

/// Uniform failure shape across every `FitnessConnector` implementation
/// (ADR-6), so the dashboard and AI analysis can react to *why* a sync
/// failed without knowing which provider they are talking to: an auth
/// failure clears the stored credentials and returns to onboarding, a
/// network failure falls back to the offline cache, a rate limit backs off.
enum ConnectorError: Error, Equatable, Sendable {
    /// The provider rejected the credentials (e.g. HTTP 401).
    case unauthorized
    /// The provider is throttling requests (e.g. HTTP 429).
    case rateLimited(retryAfter: TimeInterval?)
    /// No network path to the provider.
    case networkUnavailable
    /// The provider answered, but its certificate chain failed the pinned-CA
    /// check (`NSPinnedDomains`, #153) or system trust evaluation — most
    /// likely something on the network is intercepting TLS. Kept apart from
    /// `.networkUnavailable`: "no connection" would send the user looking for
    /// reception when they should be leaving the network.
    case untrustedConnection
    /// The provider is down or erroring server-side (e.g. HTTP 5xx).
    case serviceUnavailable
    /// The response did not match the shape the connector expects.
    case invalidResponse
    /// The connector exists only as a stub and cannot serve this call yet —
    /// thrown by every `StravaConnector` method until the OAuth flow and the
    /// Strava mapping land in v1 (ADR-6, #35). Distinct from
    /// `serviceUnavailable`: nothing is wrong on the provider's side and a
    /// retry will never succeed.
    case notImplemented
}
