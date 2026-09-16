import Foundation

/// Stable account identifiers for every item stored in the Keychain.
///
/// The raw value is used as `kSecAttrAccount`. Values are namespaced with the
/// `fitbuddy.` prefix so they never collide with other generic passwords that
/// might share the same service.
enum KeychainKey: String, CaseIterable {
    /// User-provided Hevy API key (BYO-key).
    case hevyAPIKey = "fitbuddy.hevy.apikey"
    /// User-provided Claude API key (BYO-key).
    case claudeAPIKey = "fitbuddy.claude.apikey"
    /// User-provided Gemini API key (BYO-key).
    case geminiAPIKey = "fitbuddy.gemini.apikey"
    /// User-provided Mistral API key (BYO-key).
    case mistralAPIKey = "fitbuddy.mistral.apikey"
    /// Client ID of the user's own Strava API application (ADR-10).
    case stravaClientID = "fitbuddy.strava.clientid"
    /// Client secret of that same application. Strava's token endpoint has no
    /// PKCE, so the secret is required for every code exchange and refresh.
    case stravaClientSecret = "fitbuddy.strava.clientsecret"
    /// Strava OAuth access token. Short-lived (6 hours).
    case stravaAccessToken = "fitbuddy.strava.accesstoken"
    /// Strava OAuth refresh token. Rotated by Strava on every refresh, so the
    /// value that comes back from a refresh has to replace the one used.
    case stravaRefreshToken = "fitbuddy.strava.refreshtoken"
    /// ISO8601 expiry of the access token, whole seconds.
    case stravaTokenExpiry = "fitbuddy.strava.expiresat"
    /// Version of the consent text the user agreed to.
    case consentVersion = "fitbuddy.consent.version"
    /// ISO8601 timestamp of when consent was given. Formatting is the caller's
    /// responsibility — the service stores and returns a plain string.
    case consentTimestamp = "fitbuddy.consent.timestamp"
}
