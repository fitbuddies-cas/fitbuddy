import Foundation

/// Persists `PolarConnector`'s OAuth tokens and its stable AccessLink
/// `member-id` (ADR-11) — the piece of the Sync-/Onboarding-Schicht that
/// `PolarConnector` itself deliberately does not own (it only holds tokens in
/// memory, see its type comment).
protocol PolarCredentialStoring: Sendable {
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
    /// Removes every Polar item — tokens and `member-id` alike.
    func clear() async throws
}
