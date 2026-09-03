import Foundation

/// Failure modes of an LLM analysis call (#29, #79).
///
/// Raised by an `LLMProviderClient` for the provider that produced it; after a
/// fallback chain, the one the orchestrator rethrows belongs to the *last*
/// provider tried. The provider's name is not carried here — `AnalysisFailure`
/// takes it from the run's attribution, so one error value stays reusable
/// across all three clients.
enum InferenceServiceError: Error, Equatable {
    /// No provider has a usable key in the Keychain — onboarding was skipped
    /// or no key was ever saved.
    case missingAPIKey
    /// The Keychain read itself failed (e.g. a locked device). Distinct from
    /// `.missingAPIKey`: the key is still stored, so routing the user back
    /// into onboarding to re-enter it would be wrong.
    case keychainUnavailable
    /// The lock after the last run has not lifted yet. Carries the instant it
    /// does.
    case cooldownActive(availableAt: Date)
    /// A call is already streaming; the analysis button must stay disabled
    /// until it finishes, but the actor enforces this independently.
    case alreadyInProgress
    /// The request never produced an HTTP response (offline, timeout, DNS…).
    case networkUnavailable
    /// The provider rejected the key (HTTP 401, or Google's 403).
    case unauthorized
    /// HTTP 429, with the provider's `Retry-After` in seconds when it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    /// The provider answered 5xx.
    case serviceUnavailable
    /// The response was not a stream this version can read.
    case invalidResponse
    /// Any other unexpected status code.
    case unexpectedStatus(Int)
    /// The provider sent an `error` SSE event mid-stream, after already
    /// answering HTTP 200 (e.g. Claude's `overloaded_error`). Carries its
    /// message.
    case streamInterrupted(message: String)
}
