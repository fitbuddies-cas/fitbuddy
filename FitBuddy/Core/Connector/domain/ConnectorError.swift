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
    /// The provider is down or erroring server-side (e.g. HTTP 5xx).
    case serviceUnavailable
    /// The response did not match the shape the connector expects.
    case invalidResponse
}
