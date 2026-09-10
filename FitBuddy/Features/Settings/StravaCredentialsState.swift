import Foundation

/// UI state of the Strava application-credentials screen (#139, US-5 AC3).
///
/// There is no `validating`: the client ID and secret cannot be checked
/// without running the whole OAuth flow, which is the connection screen's job.
/// Saving stores them as entered; a wrong secret shows up on the first
/// "Connect with Strava", not here.
enum StravaCredentialsState: Equatable {
    /// `bootstrap()` has not read the Keychain yet.
    case unknown
    /// Waiting for input.
    case idle
    /// Writing to the Keychain.
    case saving
    /// The last save failed. Only `.keychain` is reachable, but the type is
    /// shared so the banner copy is.
    case failed(APIKeyEntryFailure)
    /// Both values are stored.
    case saved
}
