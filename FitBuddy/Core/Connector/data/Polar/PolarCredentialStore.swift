import Foundation

/// Keychain-backed `PolarCredentialStoring` (ADR-11, issue #154).
///
/// Mirrors `PolarConnector`'s own split: the connector never touches the
/// Keychain, this actor is the only thing that does, on behalf of whatever
/// onboarding/sync code owns the connector's lifecycle.
actor PolarCredentialStore: PolarCredentialStoring {
    private let keychain: any KeychainStoring

    init(keychain: any KeychainStoring = KeychainService()) {
        self.keychain = keychain
    }

    func credentials() async throws -> ConnectorCredentials? {
        guard let accessToken = try await keychain.read(.polarAccessToken),
              let refreshToken = try await keychain.read(.polarRefreshToken),
              let expiryRaw = try await keychain.read(.polarTokenExpiry),
              let expiresAt = ISO8601DateFormatter().date(from: expiryRaw) else {
            return nil
        }
        return .oauth(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    /// Writes all three token items, rolling back whatever it already wrote
    /// if a later write fails — a partial token triple is worse than none,
    /// since `credentials()` would otherwise read back stale, mismatched
    /// values instead of `nil`. Pattern from `LLMKeysViewModel.save()`.
    func saveTokens(accessToken: String, refreshToken: String, expiresAt: Date) async throws {
        let expiryRaw = ISO8601DateFormatter().string(from: expiresAt)
        var written: [KeychainKey] = []
        do {
            try await keychain.save(accessToken, for: .polarAccessToken)
            written.append(.polarAccessToken)
            try await keychain.save(refreshToken, for: .polarRefreshToken)
            written.append(.polarRefreshToken)
            try await keychain.save(expiryRaw, for: .polarTokenExpiry)
        } catch {
            for key in written {
                try? await keychain.delete(key)
            }
            throw error
        }
    }

    func memberID() async throws -> String? {
        try await keychain.read(.polarMemberID)
    }

    func saveMemberID(_ memberID: String) async throws {
        try await keychain.save(memberID, for: .polarMemberID)
    }

    func clear() async throws {
        try await keychain.delete(.polarAccessToken)
        try await keychain.delete(.polarRefreshToken)
        try await keychain.delete(.polarTokenExpiry)
        try await keychain.delete(.polarMemberID)
    }
}
