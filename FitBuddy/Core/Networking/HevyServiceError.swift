import Foundation

/// Failure modes of a Hevy workout sync.
///
/// The cases mirror the `ConnectorError` contract in ADR-006, so the refactor
/// onto `FitnessConnector` (#34) is a rename rather than a re-design. Callers
/// must be able to tell an auth failure (key is gone → onboarding) from a
/// network failure (keep showing cached data).
enum HevyServiceError: Error, Equatable {
    /// No Hevy key in the Keychain — onboarding never completed, or a previous
    /// 401 already wiped it.
    case missingAPIKey
    /// The Keychain refused the read (e.g. `errSecInteractionNotAllowed` while
    /// the device is locked). The key is still stored — this is retryable and
    /// must not route the user back into onboarding.
    case keychainUnavailable
    /// Hevy rejected the key (HTTP 401). The hard logout has already run.
    case unauthorized
    /// HTTP 429, with Hevy's `Retry-After` in seconds when it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    /// The request never produced an HTTP response (offline, timeout, DNS…).
    case networkUnavailable
    /// Hevy answered 5xx.
    case serviceUnavailable
    /// The response was not a JSON payload this version can read.
    case invalidResponse
    /// Any other unexpected status code (e.g. 403 from a WAF).
    case unexpectedStatus(Int)
    /// The workouts were fetched but could not be written to SwiftData.
    case persistenceFailed
}
