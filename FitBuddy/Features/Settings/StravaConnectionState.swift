import Foundation

/// UI state of the Strava connection screen (#140, US-5 AC1).
///
/// Three of these come straight from `ConnectorConnectionState`; the rest are
/// what the screen adds around the OAuth flow: whether the user has entered
/// their application credentials yet, whether the browser sheet is up, and
/// what went wrong.
enum StravaConnectionState: Equatable {
    /// `bootstrap()` has not read the stores yet.
    case unknown
    /// No client ID and secret stored — nothing to authorize with.
    case missingCredentials
    /// Credentials stored, no token pair. "Connect" is available.
    case idle
    /// The browser sheet is up, or the code is being exchanged.
    case authorizing
    /// A token pair is in place and usable until `expiresAt`.
    case connected(expiresAt: Date)
    /// The token pair ran out; only the user can renew it (US-5 AC2).
    case expired(since: Date)
    /// The last connect attempt failed for a reason worth showing.
    case failed(StravaConnectionFailure)
}
