import Foundation

/// UI state of the Polar connection screen (#157, US-5 AC1).
///
/// Slimmer than `StravaConnectionState`: there is no `.missingCredentials` —
/// Polar is a PKCE public client with a team-wide `clientID` (ADR-11), so
/// there is no per-user application to set up before "Connect" makes sense.
enum PolarConnectionState: Equatable {
    /// `bootstrap()` has not read the store yet.
    case unknown
    /// No token pair stored. "Connect" is available.
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
