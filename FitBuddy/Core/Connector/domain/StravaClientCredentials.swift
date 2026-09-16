import Foundation

/// The client half of Strava's OAuth2 flow: the credentials of the API
/// application the *user* registered at `strava.com/settings/api` (ADR-10).
///
/// These are not tokens and they do not expire. They identify the application
/// that asks for authorization, and Strava's token endpoint requires both on
/// every code exchange and every refresh — it does not support PKCE, which is
/// why a public client still has to carry a secret at all.
///
/// FitBuddy never ships a client secret of its own; this one belongs to the
/// user and lives only in their Keychain.
struct StravaClientCredentials: Equatable, Sendable {
    let clientID: String
    let clientSecret: String

    init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}
