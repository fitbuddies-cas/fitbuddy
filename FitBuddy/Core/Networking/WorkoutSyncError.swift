import Foundation

/// Failure modes of a workout sync — the provider's own failures plus the
/// three the sync itself owns (Keychain, missing key, cache write).
///
/// `ConnectorError` (ADR-6) deliberately covers only what a provider can go
/// wrong with; reading the stored key and writing the local cache happen
/// around the connector, and the dashboard has to tell those apart too: a
/// locked Keychain is retryable, a failed cache write says the workouts
/// arrived but were not saved. Callers must further be able to tell an auth
/// failure (key is gone → onboarding) from a network failure (keep showing
/// cached data).
enum WorkoutSyncError: Error, Equatable {
    /// No key in the Keychain — onboarding never completed, or a previous 401
    /// already wiped it.
    case missingAPIKey
    /// The Keychain refused the read (e.g. `errSecInteractionNotAllowed` while
    /// the device is locked). The key is still stored — this is retryable and
    /// must not route the user back into onboarding.
    case keychainUnavailable
    /// The source rejected the key (HTTP 401). The hard logout has already run.
    case unauthorized
    /// HTTP 429, with the source's `Retry-After` in seconds when it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    /// The request never produced an HTTP response (offline, timeout, DNS…).
    case networkUnavailable
    /// The source answered with a certificate FitBuddy must not trust
    /// (failed pinning, #153).
    case untrustedConnection
    /// The source answered 5xx.
    case serviceUnavailable
    /// The response was not something this version can read — malformed JSON,
    /// or an unexpected status such as 403 from a WAF.
    case invalidResponse
    /// The workouts were fetched but could not be written to SwiftData.
    case persistenceFailed
    /// The source cannot sync yet — its connector is still a stub (#35).
    /// Unreachable while Hevy is the only synced source; it exists so the lift
    /// below stays a complete 1:1 mapping instead of folding a permanent
    /// failure into a retryable one.
    case notImplemented

    /// Lifts a connector failure into the sync's own vocabulary. Every
    /// `ConnectorError` case has exactly one counterpart here — the enum adds
    /// cases, it does not reinterpret any.
    init(connectorError: ConnectorError) {
        switch connectorError {
        case .unauthorized:
            self = .unauthorized
        case .rateLimited(let retryAfter):
            self = .rateLimited(retryAfter: retryAfter)
        case .networkUnavailable:
            self = .networkUnavailable
        case .untrustedConnection:
            self = .untrustedConnection
        case .serviceUnavailable:
            self = .serviceUnavailable
        case .invalidResponse:
            self = .invalidResponse
        case .notImplemented:
            self = .notImplemented
        }
    }
}
