import Foundation

/// Why the last Hevy sync did not go through — the reason the offline banner
/// names (#28).
///
/// Deliberately coarser than `WorkoutSyncError`: the user needs to know whether
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
    /// The source answered, but not with something this version can read (bad
    /// JSON, an unexpected status such as 403 from a WAF).
    case unreadableResponse
    /// The workouts arrived but could not be written to the local cache.
    case cacheWriteFailed
    /// Anything the banner has no dedicated wording for: an error that is not
    /// a `WorkoutSyncError`, or a source whose connector is still a stub
    /// (`.notImplemented`, #35) — nothing the user can act on either way.
    case unknown
    /// A secondary source rejected its token pair and only the user can
    /// renew it (#143, US-5 AC2). Unlike the Hevy key, nothing was wiped: the
    /// connection is still there, it just no longer works.
    case connectionExpired

    /// Maps a sync error onto a banner reason.
    ///
    /// - Returns: `nil` for the two auth failures. They are not banner
    ///   material: the stored key is gone, so the only honest response is
    ///   routing back to onboarding for a new one (US-1 AC3).
    init?(syncError: Error) {
        guard let error = syncError as? WorkoutSyncError else {
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
        case .invalidResponse:
            self = .unreadableResponse
        case .persistenceFailed:
            self = .cacheWriteFailed
        case .notImplemented:
            self = .unknown
        }
    }

    /// Maps one source's failure inside a partial sync (#143).
    ///
    /// The same table as `init(syncError:)`, with one difference: a rejected
    /// token for a source other than Hevy is not the end of the session — it
    /// is the renewal case US-5 AC2 describes, and it gets a banner.
    init?(syncError: WorkoutSyncError, source: ConnectorSource) {
        if source != .hevy, syncError == .unauthorized {
            self = .connectionExpired
            return
        }
        self.init(syncError: syncError)
    }

    /// Short reason shown after the sync timestamp in the banner's subtitle.
    var summary: String {
        switch self {
        case .connectionExpired:
            return "connection needs renewing"
        case .offline:
            return "no connection"
        case .serviceUnavailable:
            return "Hevy unavailable"
        case .rateLimited(let retryAfter):
            // Hevy's own `Retry-After` is the only part of a rate limit the
            // user can act on: without it "too many requests" leaves them
            // pulling to refresh into a wall they cannot see the end of.
            guard let wait = Self.wait(retryAfter) else { return "too many requests" }
            return "too many requests, retry in \(wait)"
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

    /// The single line the toast shows after a refresh the user asked for
    /// failed (#43, US-10 AC2).
    ///
    /// Written to stand on its own, unlike `summary`, which is a fragment glued
    /// behind the sync timestamp. It names what went wrong and, where there is
    /// one, what the user can do about it: this toast is the only feedback a
    /// repeated failure gives them, so "something went wrong" would waste it.
    var refreshMessage: String {
        switch self {
        case .connectionExpired:
            return "A connected source needs renewing. Reconnect it in Settings."
        case .offline:
            return "No connection. Your cached data is still here."
        case .serviceUnavailable:
            return "Hevy is unavailable right now. Your cached data is still here."
        case .rateLimited(let retryAfter):
            guard let wait = Self.wait(retryAfter) else {
                return "Too many requests to Hevy. Try again in a moment."
            }
            return "Too many requests to Hevy. Try again in \(wait)."
        case .keychainUnavailable:
            return "Your Hevy key could not be read. Unlock this device and try again."
        case .unreadableResponse:
            return "Hevy sent something FitBuddy could not read."
        case .cacheWriteFailed:
            return "Your workouts arrived but could not be saved on this device."
        case .unknown:
            return "The refresh did not go through. Your cached data is still here."
        }
    }

    /// The symbol shown next to the banner text.
    ///
    /// Per reason, not one offline glyph for all of them: a crossed-out
    /// antenna next to "key not readable" tells a user with a locked device to
    /// go looking for their reception, and the icon is what they read first.
    var symbolName: String {
        switch self {
        case .connectionExpired:
            return "exclamationmark.arrow.circlepath"
        case .offline:
            return "antenna.radiowaves.left.and.right.slash"
        case .serviceUnavailable, .rateLimited:
            return "exclamationmark.icloud"
        case .keychainUnavailable:
            return "lock.slash"
        case .unreadableResponse:
            return "questionmark.circle"
        case .cacheWriteFailed:
            return "externaldrive.badge.exclamationmark"
        case .unknown:
            return "exclamationmark.triangle"
        }
    }

    /// `30` → `"30 s"`, `180` → `"3 min"`. `nil` when Hevy sent no usable
    /// value, so the caller can drop the clause instead of printing "0 s".
    private static func wait(_ retryAfter: TimeInterval?) -> String? {
        guard let retryAfter, retryAfter >= 1 else { return nil }
        guard retryAfter >= 90 else { return "\(Int(retryAfter.rounded())) s" }
        return "\(Int((retryAfter / 60).rounded())) min"
    }
}
