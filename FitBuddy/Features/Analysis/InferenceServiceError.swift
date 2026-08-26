import Foundation

/// Failure modes of an LLM analysis call (#29).
enum InferenceServiceError: Error, Equatable {
    /// No usable provider key in the Keychain — onboarding was skipped or the
    /// key was never saved.
    case missingAPIKey
    /// Every provider the user configured in step 3 is stored, but none of
    /// them can be called by this build yet (Gemini/Mistral land with #79).
    /// Carries the highest-priority configured provider so the UI can name it
    /// and point the user at adding a Claude key.
    case providerNotSupportedYet(LLMProvider)
    /// The Keychain read itself failed (e.g. a locked device). Distinct from
    /// `.missingAPIKey`: the key is still stored, so routing the user back
    /// into onboarding to re-enter it would be wrong.
    case keychainUnavailable
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
    /// Claude sent an `error` SSE event mid-stream, after already answering
    /// HTTP 200 (e.g. `overloaded_error`). Carries Claude's error message.
    case streamInterrupted(message: String)
}
