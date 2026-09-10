import Security
import XCTest
@testable import FitBuddy

/// Unit tests for `StravaCredentialStore` (#137, ADR-10).
///
/// The round-trip and protection-class tests run against the real Keychain on
/// the simulator, like `KeychainServiceTests`. The rollback tests use an
/// in-memory double, because the real Keychain cannot be made to fail on a
/// chosen item.
final class StravaCredentialStoreTests: XCTestCase {
    private var keychain: KeychainService!
    private var sut: StravaCredentialStore!

    /// Whole seconds, as Strava's integer `expires_at` delivers them.
    private let expiry = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        try await clearAllKeys()
        sut = StravaCredentialStore(keychain: keychain)
    }

    override func tearDown() async throws {
        try await clearAllKeys()
        sut = nil
        keychain = nil
        try await super.tearDown()
    }

    private func clearAllKeys() async throws {
        for key in KeychainKey.allCases {
            try await keychain.delete(key)
        }
    }

    // MARK: - Client credentials

    func testClientCredentialsIsNilWhenNothingStored() async throws {
        let credentials = try await sut.clientCredentials()
        XCTAssertNil(credentials)
    }

    func testSaveClientCredentialsRoundtrip() async throws {
        let credentials = StravaClientCredentials(clientID: "123456", clientSecret: "s3cr3t")
        try await sut.saveClientCredentials(credentials)

        let stored = try await sut.clientCredentials()
        XCTAssertEqual(stored, credentials)
    }

    /// A client ID without a secret is not usable for a token exchange, so the
    /// store reports "not configured" rather than handing out half a pair.
    func testClientCredentialsIsNilWhenSecretIsMissing() async throws {
        try await keychain.save("123456", for: .stravaClientID)

        let credentials = try await sut.clientCredentials()
        XCTAssertNil(credentials)
    }

    /// An empty string is treated as absent: it would only produce a request
    /// Strava rejects, and the caller has no use for the distinction.
    func testClientCredentialsIsNilWhenSecretIsEmpty() async throws {
        try await keychain.save("123456", for: .stravaClientID)
        try await keychain.save("", for: .stravaClientSecret)

        let credentials = try await sut.clientCredentials()
        XCTAssertNil(credentials)
    }

    // MARK: - Tokens

    func testCredentialsIsNilWhenNothingStored() async throws {
        let credentials = try await sut.credentials()
        XCTAssertNil(credentials)
    }

    func testSaveTokensRoundtripYieldsOAuthCredentials() async throws {
        try await sut.saveTokens(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: expiry)

        let credentials = try await sut.credentials()
        XCTAssertEqual(
            credentials,
            .oauth(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: expiry)
        )
    }

    /// Guards the stored format: whole-second ISO8601 round-trips exactly, so
    /// `expiresAt` compares equal and the connector's refresh window stays
    /// accurate to the second.
    func testStoredExpiryRoundtripsExactly() async throws {
        try await sut.saveTokens(accessToken: "a", refreshToken: "r", expiresAt: expiry)

        let raw = try await keychain.read(.stravaTokenExpiry)
        XCTAssertEqual(raw, "2027-01-15T08:00:00Z")

        guard case .oauth(_, _, let readBack)? = try await sut.credentials() else {
            return XCTFail("expected oauth credentials")
        }
        XCTAssertEqual(readBack, expiry)
    }

    /// Never a half `.oauth`: without the refresh token the pair would fail on
    /// the first refresh, with nothing to tell the user why.
    func testCredentialsIsNilWhenRefreshTokenIsMissing() async throws {
        try await keychain.save("access-1", for: .stravaAccessToken)
        try await keychain.save("2027-01-15T08:00:00Z", for: .stravaTokenExpiry)

        let credentials = try await sut.credentials()
        XCTAssertNil(credentials)
    }

    func testCredentialsIsNilWhenExpiryCannotBeParsed() async throws {
        try await keychain.save("access-1", for: .stravaAccessToken)
        try await keychain.save("refresh-1", for: .stravaRefreshToken)
        try await keychain.save("not-a-date", for: .stravaTokenExpiry)

        let credentials = try await sut.credentials()
        XCTAssertNil(credentials)
    }

    // MARK: - Protection class

    /// Every Strava item must carry the same protection class as the other
    /// secrets (ADR-3): no iCloud sync, no access while locked.
    func testStoredItemsUseWhenUnlockedThisDeviceOnly() async throws {
        try await sut.saveClientCredentials(
            StravaClientCredentials(clientID: "123456", clientSecret: "s3cr3t")
        )
        try await sut.saveTokens(accessToken: "a", refreshToken: "r", expiresAt: expiry)

        let stravaKeys: [KeychainKey] = [
            .stravaClientID, .stravaClientSecret,
            .stravaAccessToken, .stravaRefreshToken, .stravaTokenExpiry,
        ]

        for key in stravaKeys {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "ch.bfh.fitbuddy",
                kSecAttrAccount as String: key.rawValue,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            XCTAssertEqual(status, errSecSuccess, "missing item for \(key.rawValue)")

            let attributes = try XCTUnwrap(result as? [String: Any])
            XCTAssertEqual(
                attributes[kSecAttrAccessible as String] as? String,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
                "wrong protection class for \(key.rawValue)"
            )
        }
    }

    /// The five items have to be in `allCases`, because that is what
    /// `DataResetService` and `FirstLaunchResetService` iterate — the deletion
    /// right depends on this and on nothing else.
    func testAllCasesCoversEveryStravaItem() {
        let raw = Set(KeychainKey.allCases.map(\.rawValue))
        for expected in [
            "fitbuddy.strava.clientid",
            "fitbuddy.strava.clientsecret",
            "fitbuddy.strava.accesstoken",
            "fitbuddy.strava.refreshtoken",
            "fitbuddy.strava.expiresat",
        ] {
            XCTAssertTrue(raw.contains(expected), "KeychainKey.allCases is missing \(expected)")
        }
    }

    // MARK: - clear

    func testClearRemovesClientCredentialsAndTokens() async throws {
        try await sut.saveClientCredentials(
            StravaClientCredentials(clientID: "123456", clientSecret: "s3cr3t")
        )
        try await sut.saveTokens(accessToken: "a", refreshToken: "r", expiresAt: expiry)

        try await sut.clear()

        let clientCredentials = try await sut.clientCredentials()
        let credentials = try await sut.credentials()
        XCTAssertNil(clientCredentials)
        XCTAssertNil(credentials)
    }

    /// Disconnecting Strava must not log the user out of Hevy (#140).
    func testClearLeavesOtherKeysUntouched() async throws {
        try await keychain.save("hv_live_abc", for: .hevyAPIKey)
        try await sut.saveTokens(accessToken: "a", refreshToken: "r", expiresAt: expiry)

        try await sut.clear()

        let hevyKey = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(hevyKey, "hv_live_abc")
    }

    /// A failing delete must not abort the remaining ones — a live token left
    /// behind because another item refused to go is the worse outcome.
    func testClearDeletesEveryItemEvenWhenOneFails() async throws {
        let stub = FlakyKeychainStub(failDeleteFor: .stravaClientSecret)
        await stub.seed("123456", for: .stravaClientID)
        await stub.seed("s3cr3t", for: .stravaClientSecret)
        await stub.seed("access-1", for: .stravaAccessToken)
        let store = StravaCredentialStore(keychain: stub)

        do {
            try await store.clear()
            XCTFail("expected the failing delete to be reported")
        } catch {
            // Expected — the error surfaces after every delete was attempted.
        }

        let attempted = await stub.deletedKeys
        XCTAssertTrue(attempted.contains(.stravaClientID))
        XCTAssertTrue(attempted.contains(.stravaAccessToken))
        XCTAssertTrue(attempted.contains(.stravaTokenExpiry))
    }

    // MARK: - Atomicity

    /// A token pair written halfway is worse than none: the next refresh would
    /// send a refresh token that no longer matches the access token.
    func testSaveTokensWritesNothingWhenALaterWriteFails() async throws {
        let stub = FlakyKeychainStub(failSaveFor: .stravaTokenExpiry)
        let store = StravaCredentialStore(keychain: stub)

        do {
            try await store.saveTokens(accessToken: "a", refreshToken: "r", expiresAt: expiry)
            XCTFail("expected the failing write to propagate")
        } catch {
            // Expected.
        }

        let access = await stub.value(for: .stravaAccessToken)
        let refresh = await stub.value(for: .stravaRefreshToken)
        let storedExpiry = await stub.value(for: .stravaTokenExpiry)
        XCTAssertNil(access)
        XCTAssertNil(refresh)
        XCTAssertNil(storedExpiry)
    }

    /// Rollback restores the previous pair rather than deleting it: a failed
    /// refresh must leave the working connection in place.
    func testSaveTokensRestoresThePreviousPairWhenAWriteFails() async throws {
        let stub = FlakyKeychainStub(failSaveFor: .stravaTokenExpiry)
        await stub.seed("old-access", for: .stravaAccessToken)
        await stub.seed("old-refresh", for: .stravaRefreshToken)
        await stub.seed("2026-01-01T00:00:00Z", for: .stravaTokenExpiry)
        let store = StravaCredentialStore(keychain: stub)

        do {
            try await store.saveTokens(accessToken: "new-access", refreshToken: "new-refresh", expiresAt: expiry)
            XCTFail("expected the failing write to propagate")
        } catch {
            // Expected.
        }

        let access = await stub.value(for: .stravaAccessToken)
        let refresh = await stub.value(for: .stravaRefreshToken)
        XCTAssertEqual(access, "old-access")
        XCTAssertEqual(refresh, "old-refresh")
    }

    func testSaveClientCredentialsWritesNothingWhenTheSecretFails() async throws {
        let stub = FlakyKeychainStub(failSaveFor: .stravaClientSecret)
        let store = StravaCredentialStore(keychain: stub)

        do {
            try await store.saveClientCredentials(
                StravaClientCredentials(clientID: "123456", clientSecret: "s3cr3t")
            )
            XCTFail("expected the failing write to propagate")
        } catch {
            // Expected.
        }

        let clientID = await stub.value(for: .stravaClientID)
        XCTAssertNil(clientID)
    }
}

/// In-memory `KeychainStoring` that can be told to fail on one chosen item.
/// The real `KeychainService` cannot be made to fail selectively on the
/// simulator, which is what the atomicity tests need.
private actor FlakyKeychainStub: KeychainStoring {
    private var stored: [KeychainKey: String] = [:]
    private let failSaveFor: KeychainKey?
    private let failDeleteFor: KeychainKey?
    private(set) var deletedKeys: [KeychainKey] = []

    init(failSaveFor: KeychainKey? = nil, failDeleteFor: KeychainKey? = nil) {
        self.failSaveFor = failSaveFor
        self.failDeleteFor = failDeleteFor
    }

    func seed(_ value: String, for key: KeychainKey) {
        stored[key] = value
    }

    func value(for key: KeychainKey) -> String? {
        stored[key]
    }

    func save(_ value: String, for key: KeychainKey) throws {
        guard key != failSaveFor else { throw KeychainError.invalidData }
        stored[key] = value
    }

    func read(_ key: KeychainKey) throws -> String? {
        stored[key]
    }

    func delete(_ key: KeychainKey) throws {
        deletedKeys.append(key)
        guard key != failDeleteFor else { throw KeychainError.invalidData }
        stored[key] = nil
    }

    func exists(_ key: KeychainKey) throws -> Bool {
        stored[key] != nil
    }
}
