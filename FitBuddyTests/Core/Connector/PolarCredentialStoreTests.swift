import XCTest
@testable import FitBuddy

/// Unit tests for `PolarCredentialStore` (issue #154). Uses the real
/// `KeychainService` on the simulator (same pattern as
/// `LLMKeysViewModelTests`), with all Polar items cleared around each test.
final class PolarCredentialStoreTests: XCTestCase {
    private var keychain: KeychainService!
    private var sut: PolarCredentialStore!

    private static let polarKeys: [KeychainKey] = [
        .polarClientID, .polarClientSecret,
        .polarAccessToken, .polarRefreshToken, .polarTokenExpiry, .polarMemberID,
    ]

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        for key in Self.polarKeys {
            try await keychain.delete(key)
        }
        sut = PolarCredentialStore(keychain: keychain)
    }

    override func tearDown() async throws {
        for key in Self.polarKeys {
            try await keychain.delete(key)
        }
        sut = nil
        keychain = nil
        try await super.tearDown()
    }

    // MARK: - Client credentials

    func testClientCredentialsIsNilWhenNothingStored() async throws {
        let credentials = try await sut.clientCredentials()
        XCTAssertNil(credentials)
    }

    func testSaveClientCredentialsRoundtrip() async throws {
        let credentials = PolarClientCredentials(clientID: "client-1", clientSecret: "s3cr3t")
        try await sut.saveClientCredentials(credentials)

        let stored = try await sut.clientCredentials()
        XCTAssertEqual(stored, credentials)
    }

    /// A client ID without a secret is not usable for a token exchange, so the
    /// store reports "not configured" rather than handing out half a pair.
    func testClientCredentialsIsNilWhenSecretIsMissing() async throws {
        try await keychain.save("client-1", for: .polarClientID)

        let credentials = try await sut.clientCredentials()
        XCTAssertNil(credentials)
    }

    // MARK: - credentials()

    func testCredentialsReturnsNilWhenNothingStored() async throws {
        let credentials = try await sut.credentials()
        XCTAssertNil(credentials)
    }

    func testCredentialsReturnsOAuthAfterSaveTokens() async throws {
        let expiresAt = Date(timeIntervalSince1970: 1_700_000_000)

        try await sut.saveTokens(accessToken: "access", refreshToken: "refresh", expiresAt: expiresAt)

        let credentials = try await sut.credentials()
        guard case .oauth(let access, let refresh, let storedExpiry) = credentials else {
            return XCTFail("Expected .oauth credentials")
        }
        XCTAssertEqual(access, "access")
        XCTAssertEqual(refresh, "refresh")
        XCTAssertEqual(storedExpiry.timeIntervalSince1970, expiresAt.timeIntervalSince1970, accuracy: 1)
    }

    func testCredentialsReturnsNilWhenOnlyPartiallyStored() async throws {
        // Simulates a store left in an inconsistent state by writing directly,
        // bypassing the SUT's atomic `saveTokens`.
        try await keychain.save("access", for: .polarAccessToken)
        try await keychain.save("refresh", for: .polarRefreshToken)
        // `.polarTokenExpiry` deliberately left unset.

        let credentials = try await sut.credentials()
        XCTAssertNil(credentials)
    }

    // MARK: - saveTokens() atomicity

    func testSaveTokensRollsBackOnFailure() async throws {
        let failing = FailingKeychainStore(failingKey: .polarTokenExpiry)
        let sut = PolarCredentialStore(keychain: failing)

        do {
            try await sut.saveTokens(accessToken: "access", refreshToken: "refresh", expiresAt: Date())
            XCTFail("Expected saveTokens to throw")
        } catch {
            // expected
        }

        let access = try await failing.read(.polarAccessToken)
        let refresh = try await failing.read(.polarRefreshToken)
        let expiry = try await failing.read(.polarTokenExpiry)
        XCTAssertNil(access)
        XCTAssertNil(refresh)
        XCTAssertNil(expiry)
    }

    // MARK: - memberID

    func testMemberIDRoundTrips() async throws {
        let initial = try await sut.memberID()
        XCTAssertNil(initial)

        try await sut.saveMemberID("member-42")

        let stored = try await sut.memberID()
        XCTAssertEqual(stored, "member-42")
    }

    // MARK: - clear()

    func testClearRemovesAllItems() async throws {
        try await sut.saveClientCredentials(PolarClientCredentials(clientID: "client-1", clientSecret: "s3cr3t"))
        try await sut.saveTokens(accessToken: "access", refreshToken: "refresh", expiresAt: Date())
        try await sut.saveMemberID("member-42")

        try await sut.clear()

        let clientCredentials = try await sut.clientCredentials()
        let credentials = try await sut.credentials()
        let memberID = try await sut.memberID()
        XCTAssertNil(clientCredentials)
        XCTAssertNil(credentials)
        XCTAssertNil(memberID)
    }

    /// Disconnecting Polar must not log the user out of Hevy.
    func testClearLeavesOtherKeysUntouched() async throws {
        try await keychain.save("hv_live_abc", for: .hevyAPIKey)
        try await sut.saveTokens(accessToken: "access", refreshToken: "refresh", expiresAt: Date())

        try await sut.clear()

        let hevyKey = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(hevyKey, "hv_live_abc")
        try await keychain.delete(.hevyAPIKey)
    }
}

/// In-memory `KeychainStoring` double that fails `save` for one designated
/// key, so `saveTokens`'s rollback path can be exercised deterministically —
/// the real `KeychainService` cannot be made to fail on demand on the
/// simulator (same rationale as `KeychainStoring`'s own doc comment).
private actor FailingKeychainStore: KeychainStoring {
    private let failingKey: KeychainKey
    private var storage: [KeychainKey: String] = [:]

    init(failingKey: KeychainKey) {
        self.failingKey = failingKey
    }

    func save(_ value: String, for key: KeychainKey) async throws {
        if key == failingKey {
            throw KeychainError.unexpectedStatus(-1)
        }
        storage[key] = value
    }

    func read(_ key: KeychainKey) async throws -> String? {
        storage[key]
    }

    func delete(_ key: KeychainKey) async throws {
        storage[key] = nil
    }

    func exists(_ key: KeychainKey) async throws -> Bool {
        storage[key] != nil
    }
}
