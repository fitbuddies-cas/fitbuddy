import Foundation

/// Stores the user's Strava application credentials and OAuth token pair in the
/// Keychain (ADR-10).
///
/// ADR-3 originally reserved a single `fitbuddy.strava.token`. The BYO-app model
/// needs five items instead — client ID, client secret, access token, refresh
/// token and expiry — and this type is the only place that knows they belong
/// together. Everything above it deals in `StravaClientCredentials` and
/// `ConnectorCredentials`.
///
/// Writes that span several items restore the previous state when one of them
/// fails, so a caller never ends up with a half-written token pair: an access
/// token whose refresh token belongs to an older pair would fail on the next
/// refresh with no way to tell why.
actor StravaCredentialStore: StravaCredentialStoring {
    private let keychain: any KeychainStoring

    /// Whole-second ISO8601, matching Strava's integer `expires_at`. Seconds
    /// precision makes the stored value round-trip exactly, so a date read back
    /// compares equal to the one written.
    private static let expiryFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(keychain: any KeychainStoring = KeychainService()) {
        self.keychain = keychain
    }

    // MARK: - Client credentials

    func clientCredentials() async throws -> StravaClientCredentials? {
        guard let clientID = try await nonEmpty(.stravaClientID),
              let clientSecret = try await nonEmpty(.stravaClientSecret)
        else { return nil }

        return StravaClientCredentials(clientID: clientID, clientSecret: clientSecret)
    }

    func saveClientCredentials(_ credentials: StravaClientCredentials) async throws {
        try await write([
            (.stravaClientID, credentials.clientID),
            (.stravaClientSecret, credentials.clientSecret),
        ])
    }

    // MARK: - Tokens

    func credentials() async throws -> ConnectorCredentials? {
        guard let accessToken = try await nonEmpty(.stravaAccessToken),
              let refreshToken = try await nonEmpty(.stravaRefreshToken),
              let rawExpiry = try await nonEmpty(.stravaTokenExpiry),
              let expiresAt = Self.expiryFormatter.date(from: rawExpiry)
        else { return nil }

        return .oauth(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    func saveTokens(accessToken: String, refreshToken: String, expiresAt: Date) async throws {
        try await write([
            (.stravaAccessToken, accessToken),
            (.stravaRefreshToken, refreshToken),
            (.stravaTokenExpiry, Self.expiryFormatter.string(from: expiresAt)),
        ])
    }

    // MARK: - Reset

    func clearTokens() async throws {
        try await delete(Self.tokenKeys)
    }

    func clear() async throws {
        try await delete(Self.ownedKeys)
    }

    /// Every delete is attempted even if an earlier one fails: leaving a
    /// live token behind because the client ID could not be removed would be
    /// the worse outcome. The first error is reported afterwards.
    private func delete(_ keys: [KeychainKey]) async throws {
        var firstError: Error?
        for key in keys {
            do {
                try await keychain.delete(key)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    // MARK: - Helpers

    /// The items this store owns. Deliberately not `KeychainKey.allCases` —
    /// clearing Strava must not touch the Hevy or LLM keys.
    static let ownedKeys: [KeychainKey] = [.stravaClientID, .stravaClientSecret] + tokenKeys

    /// The three items that make up the token pair.
    private static let tokenKeys: [KeychainKey] = [
        .stravaAccessToken,
        .stravaRefreshToken,
        .stravaTokenExpiry,
    ]

    /// Reads `key`, treating an empty string as absent: for every caller here
    /// a blank secret is not usable, and the distinction would only produce a
    /// request that Strava rejects.
    private func nonEmpty(_ key: KeychainKey) async throws -> String? {
        guard let value = try await keychain.read(key), !value.isEmpty else { return nil }
        return value
    }

    /// Writes all pairs or none of them.
    ///
    /// The previous value of each item is captured before it is overwritten, so
    /// a failure halfway through can put the items back as they were — an item
    /// that did not exist before is deleted again.
    private func write(_ values: [(KeychainKey, String)]) async throws {
        var undo: [(KeychainKey, String?)] = []
        do {
            for (key, value) in values {
                undo.append((key, try await keychain.read(key)))
                try await keychain.save(value, for: key)
            }
        } catch {
            // Best effort, in reverse order. A failing rollback leaves the
            // Keychain no worse off than not attempting one.
            for (key, previous) in undo.reversed() {
                if let previous {
                    try? await keychain.save(previous, for: key)
                } else {
                    try? await keychain.delete(key)
                }
            }
            throw error
        }
    }
}
