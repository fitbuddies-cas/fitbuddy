import Foundation

/// Persists `PolarConnector`'s OAuth tokens, its stable AccessLink
/// `member-id`, and (ADR-11) the user's own Polar API application
/// credentials — the piece of the Sync-/Onboarding-Schicht that
/// `PolarConnector` itself deliberately does not own (it only holds tokens in
/// memory, see its type comment). Mirrors `StravaCredentialStoring`.
protocol PolarCredentialStoring: Sendable {
    /// The user's registered application, or `nil` if it has not been entered.
    func clientCredentials() async throws -> PolarClientCredentials?

    /// Replaces the stored application credentials.
    func saveClientCredentials(_ credentials: PolarClientCredentials) async throws

    /// The stored token pair as `ConnectorCredentials.oauth`, or `nil` when
    /// any one of the three token items is missing — never a half credential.
    func credentials() async throws -> ConnectorCredentials?
    /// Overwrites the stored access/refresh token and expiry.
    func saveTokens(accessToken: String, refreshToken: String, expiresAt: Date) async throws
    /// FitBuddy's own stable AccessLink `member-id`, or `nil` before the user
    /// has ever connected.
    func memberID() async throws -> String?
    /// Stores the `member-id` returned by (or already known from) AccessLink
    /// registration.
    func saveMemberID(_ memberID: String) async throws
    /// Removes every Polar item — application credentials, tokens and
    /// `member-id` alike.
    func clear() async throws
}
