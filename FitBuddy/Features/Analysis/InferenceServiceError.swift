import Foundation

/// Failure modes of a Claude analysis call (#29).
enum InferenceServiceError: Error, Equatable {
    /// No Claude key in the Keychain — onboarding was skipped or the key was
    /// never saved.
    case missingAPIKey
    /// The 6h cooldown has not elapsed yet. Carries the instant it will.
    case cooldownActive(availableAt: Date)
    /// A call is already streaming; the analysis button must stay disabled
    /// until it finishes, but the actor enforces this independently.
    case alreadyInProgress
    /// The request never produced an HTTP response (offline, timeout, DNS…).
    case networkUnavailable
    /// Claude rejected the key (HTTP 401).
    case unauthorized
    /// HTTP 429, with Claude's `Retry-After` in seconds when it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    /// Claude answered 5xx.
    case serviceUnavailable
    /// The response was not a stream this version can read.
    case invalidResponse
    /// Any other unexpected status code.
    case unexpectedStatus(Int)
}
