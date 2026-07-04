import Foundation

/// Failure modes when validating a Hevy API key against the Hevy API.
enum HevyKeyValidationError: Error, Equatable {
    /// Hevy rejected the key (HTTP 401).
    case invalidKey
    /// The request never produced an HTTP response (offline, timeout, DNS…).
    case transport
    /// Hevy answered with an unexpected status code (5xx, rate limit…).
    case unexpectedStatus(Int)
}
