import Foundation

/// Persistence seam for everything Strava needs to authenticate (ADR-10).
///
/// Split from `KeychainStoring` because callers care about two whole
/// credentials — the user's application and the current token pair — not about
/// the five individual Keychain items they are made of. It also lets view
/// models and the connector be tested against a store that can fail on demand.
protocol StravaCredentialStoring: Sendable {
    /// The user's registered application, or `nil` if it has not been entered.
    func clientCredentials() async throws -> StravaClientCredentials?

    /// Replaces the stored application credentials.
    func saveClientCredentials(_ credentials: StravaClientCredentials) async throws

    /// The current token pair as the connector contract expects it, or `nil`
    /// when no complete pair is stored.
    func credentials() async throws -> ConnectorCredentials?

    /// Replaces the stored token pair. Called after the initial authorization
    /// and after every refresh.
    func saveTokens(accessToken: String, refreshToken: String, expiresAt: Date) async throws

    /// Removes application credentials and tokens alike.
    func clear() async throws
}
