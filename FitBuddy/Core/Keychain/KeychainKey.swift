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
    /// Version of the consent text the user agreed to.
    case consentVersion = "fitbuddy.consent.version"
    /// ISO8601 timestamp of when consent was given. Formatting is the caller's
    /// responsibility — the service stores and returns a plain string.
    case consentTimestamp = "fitbuddy.consent.timestamp"
}
