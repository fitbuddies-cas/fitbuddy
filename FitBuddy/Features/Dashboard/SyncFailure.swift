import Foundation

/// Why the last Hevy sync did not go through — the reason the offline banner
/// names (#28).
///
/// Deliberately coarser than `HevyServiceError`: the user needs to know whether
/// waiting helps, not which status code arrived. The one distinction the AC
/// insists on — a network failure versus an HTTP failure — survives, because
/// `offline` and the server-side cases stay separate.
enum SyncFailure: Equatable {
    /// The request never reached Hevy (no connection, DNS, timeout).
    case offline
    /// Hevy answered 5xx — the app is fine, the service is not.
    case serviceUnavailable
    /// HTTP 429, with Hevy's `Retry-After` in seconds when it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    /// The Keychain refused the key read, e.g. on a locked device. Retryable,
    /// and explicitly *not* a reason to send the user back to onboarding.
    case keychainUnavailable
    /// Hevy answered, but not with something this version can read (bad JSON,
    /// an unexpected status such as 403 from a WAF).
    case unreadableResponse
    /// The workouts arrived but could not be written to the local cache.
    case cacheWriteFailed
    /// Anything the sync surfaced that is not a `HevyServiceError`.
    case unknown

    /// Maps a sync error onto a banner reason.
    ///
    /// - Returns: `nil` for the two auth failures. They are not banner
    ///   material: the stored key is gone, so the only honest response is
    ///   routing back to onboarding for a new one (US-1 AC3).
    init?(syncError: Error) {
        guard let error = syncError as? HevyServiceError else {
            self = .unknown
            return
        }
        switch error {
        case .unauthorized, .missingAPIKey:
            return nil
        case .networkUnavailable:
            self = .offline
        case .serviceUnavailable:
            self = .serviceUnavailable
        case .rateLimited(let retryAfter):
            self = .rateLimited(retryAfter: retryAfter)
        case .keychainUnavailable:
            self = .keychainUnavailable
        case .invalidResponse, .unexpectedStatus:
            self = .unreadableResponse
        case .persistenceFailed:
            self = .cacheWriteFailed
        }
    }

    /// Short reason shown after the sync timestamp in the banner's subtitle.
    var summary: String {
        switch self {
        case .offline:
            return "no connection"
        case .serviceUnavailable:
            return "Hevy unavailable"
        case .rateLimited:
            return "too many requests"
        case .keychainUnavailable:
            return "key not readable"
        case .unreadableResponse:
            return "unexpected response"
        case .cacheWriteFailed:
            return "could not be saved"
        case .unknown:
            return "sync failed"
        }
    }
}
