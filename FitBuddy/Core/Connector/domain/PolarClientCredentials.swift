import Foundation

/// The client half of Polar's OAuth2 flow: the credentials of the API
/// application the *user* registered at `admin.polaraccesslink.com` (ADR-11
/// Nachtrag, mirrors `StravaClientCredentials`/ADR-10).
///
/// These are not tokens and they do not expire. Polar's token endpoint
/// requires both on every code exchange and every refresh via HTTP Basic
/// auth — PKCE does not replace the secret, contrary to this ADR's original
/// assumption (see the Nachtrag).
///
/// FitBuddy never ships a client secret of its own; this one belongs to the
/// user and lives only in their Keychain.
struct PolarClientCredentials: Equatable, Sendable {
    let clientID: String
    let clientSecret: String

    init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}
