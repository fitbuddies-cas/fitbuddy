import Security
import XCTest
@testable import FitBuddy

/// Unit tests for `KeychainService`. These run against the real Keychain on the
/// simulator; `setUp`/`tearDown` clear the FitBuddy test keys to keep runs
/// isolated and repeatable.
final class KeychainServiceTests: XCTestCase {
    private var sut: KeychainService!

    override func setUp() async throws {
        try await super.setUp()
        sut = KeychainService()
        try await clearAllKeys()
    }

    override func tearDown() async throws {
        try await clearAllKeys()
        sut = nil
        try await super.tearDown()
    }

    private func clearAllKeys() async throws {
        for key in KeychainKey.allCases {
            try await sut.delete(key)
        }
    }

    // MARK: - read / save

    func testReadMissingKeyReturnsNil() async throws {
        let value = try await sut.read(.hevyAPIKey)
        XCTAssertNil(value)
    }

    func testSaveThenReadRoundtrip() async throws {
        try await sut.save("hevy-secret", for: .hevyAPIKey)
        let value = try await sut.read(.hevyAPIKey)
        XCTAssertEqual(value, "hevy-secret")
    }

    func testSaveTwiceUpdatesValue() async throws {
        try await sut.save("first", for: .claudeAPIKey)
        try await sut.save("second", for: .claudeAPIKey)
        let value = try await sut.read(.claudeAPIKey)
        XCTAssertEqual(value, "second")
    }

    func testSaveEmptyStringIsAllowed() async throws {
        try await sut.save("", for: .consentVersion)
        let value = try await sut.read(.consentVersion)
        XCTAssertEqual(value, "")
    }

    // MARK: - exists

    func testExistsReflectsState() async throws {
        let before = try await sut.exists(.consentTimestamp)
        XCTAssertFalse(before)

        try await sut.save("2026-06-24T10:00:00Z", for: .consentTimestamp)
        let after = try await sut.exists(.consentTimestamp)
        XCTAssertTrue(after)
    }

    // MARK: - accessibility attribute

    func testSavedItemUsesWhenUnlockedThisDeviceOnly() async throws {
        try await sut.save("secret", for: .hevyAPIKey)

        // Read the stored item's attributes back directly, bypassing the SUT,
        // to verify the accessibility promise in the header doc comment.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ch.bfh.fitbuddy",
            kSecAttrAccount as String: KeychainKey.hevyAPIKey.rawValue,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess)

        let attributes = try XCTUnwrap(result as? [String: Any])
        let accessible = attributes[kSecAttrAccessible as String] as? String
        XCTAssertEqual(accessible, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    // MARK: - delete

    func testDeleteRemovesValue() async throws {
        try await sut.save("to-delete", for: .hevyAPIKey)
        try await sut.delete(.hevyAPIKey)
        let value = try await sut.read(.hevyAPIKey)
        XCTAssertNil(value)
    }

    func testDeleteMissingKeyDoesNotThrow() async throws {
        try await sut.delete(.claudeAPIKey)
    }

    // MARK: - key isolation

    func testKeysAreStoredIndependently() async throws {
        try await sut.save("hevy", for: .hevyAPIKey)
        try await sut.save("claude", for: .claudeAPIKey)
        try await sut.save("v0", for: .consentVersion)
        try await sut.save("2026-06-24T10:00:00Z", for: .consentTimestamp)

        let hevy = try await sut.read(.hevyAPIKey)
        let claude = try await sut.read(.claudeAPIKey)
        let version = try await sut.read(.consentVersion)
        let timestamp = try await sut.read(.consentTimestamp)

        XCTAssertEqual(hevy, "hevy")
        XCTAssertEqual(claude, "claude")
        XCTAssertEqual(version, "v0")
        XCTAssertEqual(timestamp, "2026-06-24T10:00:00Z")

        // Deleting one key leaves the others untouched.
        try await sut.delete(.hevyAPIKey)
        let deletedHevy = try await sut.read(.hevyAPIKey)
        let remainingClaude = try await sut.read(.claudeAPIKey)
        XCTAssertNil(deletedHevy)
        XCTAssertEqual(remainingClaude, "claude")
    }
}
