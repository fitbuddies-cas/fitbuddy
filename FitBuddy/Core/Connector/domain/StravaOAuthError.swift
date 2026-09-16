import Foundation

/// Everything that can go wrong between "Connect with Strava" and a stored token
/// pair (ADR-10). One case per distinct thing the UI should say, because the
/// most likely mistake — a mis-set callback domain in the user's Strava
/// application — shows up in the web sheet, not in the app, and a generic
/// "something failed" would send the user to the wrong screen.
///
/// No case carries a token or secret, so any of these can be logged or shown.
enum StravaOAuthError: Error, Equatable, Sendable {
    /// The user dismissed the sheet. Not an error to display.
    case cancelled
    /// The user declined on Strava's authorization page.
    case accessDenied
    /// The callback's `state` is not the one we sent. The callback is not ours.
    case stateMismatch
    /// The user authorized, but without `activity:read_all`.
    case missingScope
    /// The callback carried neither a code nor a known error.
    case invalidCallback
    /// Strava rejected the client ID or secret. Points at the credentials screen.
    case invalidClientCredentials
    /// Strava rejected the authorization code or the refresh token. Points at
    /// reconnecting, not at the credentials.
    case invalidGrant
    /// A 2xx whose body was not the token document we expect.
    case invalidResponse
    /// No HTTP response at all: offline, DNS, timeout.
    case transport
    /// Any other status from the token endpoint.
    case unexpectedStatus(Int)
}
