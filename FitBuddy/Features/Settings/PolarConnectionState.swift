import Foundation

/// UI state of the Polar connection screen (#157, US-5 AC1).
///
/// Mirrors `StravaConnectionState` (ADR-11, BYO-app): Polar's token
/// endpoint requires the user's own application credentials just like
/// Strava's does.
enum PolarConnectionState: Equatable {
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
    case failed(PolarConnectionFailure)
}
