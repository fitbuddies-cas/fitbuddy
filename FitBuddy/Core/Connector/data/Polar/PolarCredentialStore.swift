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

    // MARK: - Client credentials

    func clientCredentials() async throws -> PolarClientCredentials? {
        guard let clientID = try await nonEmpty(.polarClientID),
              let clientSecret = try await nonEmpty(.polarClientSecret)
        else { return nil }

        return PolarClientCredentials(clientID: clientID, clientSecret: clientSecret)
    }

    func saveClientCredentials(_ credentials: PolarClientCredentials) async throws {
        var written: [KeychainKey] = []
        do {
            try await keychain.save(credentials.clientID, for: .polarClientID)
            written.append(.polarClientID)
            try await keychain.save(credentials.clientSecret, for: .polarClientSecret)
        } catch {
            for key in written {
                try? await keychain.delete(key)
            }
            throw error
        }
    }

    /// Reads `key`, treating an empty string as absent: for every caller here
    /// a blank secret is not usable, and the distinction would only produce a
    /// request that Polar rejects.
    private func nonEmpty(_ key: KeychainKey) async throws -> String? {
        guard let value = try await keychain.read(key), !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Tokens

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
        // Every delete is attempted even if an earlier one fails: leaving a
        // live token behind because the client ID could not be removed would be
        // the worse outcome. The first error is reported afterwards.
        var firstError: Error?
        for key in Self.ownedKeys {
            do {
                try await keychain.delete(key)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    /// The items this store owns. Deliberately not `KeychainKey.allCases` —
    /// clearing Polar must not touch the Hevy or Strava keys.
    private static let ownedKeys: [KeychainKey] = [
        .polarClientID,
        .polarClientSecret,
        .polarAccessToken,
        .polarRefreshToken,
        .polarTokenExpiry,
        .polarMemberID,
    ]
}
