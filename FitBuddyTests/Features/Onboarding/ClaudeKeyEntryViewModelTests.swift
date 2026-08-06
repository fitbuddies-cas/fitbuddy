import XCTest
@testable import FitBuddy

/// Unit tests for `ClaudeKeyEntryViewModel`. Keychain access uses the real
/// `KeychainService` on the simulator (same pattern as
/// `HevyKeyEntryViewModelTests`), with the Claude key cleared around each
/// test; the skip flag uses an isolated `UserDefaults` suite (same pattern as
/// `FirstLaunchResetServiceTests`).
@MainActor
final class ClaudeKeyEntryViewModelTests: XCTestCase {
    private var keychain: KeychainService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: ClaudeKeyEntryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        try await keychain.delete(.claudeAPIKey)
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = ClaudeKeyEntryViewModel(keychain: keychain, defaults: defaults)
    }

    override func tearDown() async throws {
        try await keychain.delete(.claudeAPIKey)
        sut = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        keychain = nil
        try await super.tearDown()
    }

    // MARK: - Input gating

    func testCanSaveRequiresNonEmptyKey() {
        XCTAssertFalse(sut.canSave)
        sut.apiKey = "   \n"
        XCTAssertFalse(sut.canSave)
        sut.apiKey = "sk-ant-abc"
        XCTAssertTrue(sut.canSave)
    }

    func testSaveWithEmptyKeyIsNoOp() async throws {
        await sut.bootstrap()
        await sut.save()
        XCTAssertEqual(sut.state, .idle)
        let stored = try await keychain.read(.claudeAPIKey)
        XCTAssertNil(stored)
    }

    // MARK: - Save (no live validation, unlike Hevy)

    func testSaveStoresTrimmedKeyAndMovesToSaved() async throws {
        sut.apiKey = "  sk-ant-abc\n"
        await sut.save()

        XCTAssertEqual(sut.state, .saved)
        let stored = try await keychain.read(.claudeAPIKey)
        XCTAssertEqual(stored, "sk-ant-abc")
    }

    // MARK: - Skip (AC2)

    func testSkipMovesToSkippedWithoutStoringAnything() async throws {
        sut.skip()
        XCTAssertEqual(sut.state, .skipped)
        let stored = try await keychain.read(.claudeAPIKey)
        XCTAssertNil(stored)
    }

    func testSkipPersistsTheDecisionToUserDefaults() {
        sut.skip()
        XCTAssertTrue(defaults.bool(forKey: "fitbuddy.onboarding.claudeKeySkipped"))
    }

    func testSkipPersistsAcrossRelaunch() async {
        sut.skip()

        // A fresh view model sharing the same stores simulates a cold start
        // after the user previously skipped.
        let relaunched = ClaudeKeyEntryViewModel(keychain: keychain, defaults: defaults)
        await relaunched.bootstrap()

        XCTAssertEqual(relaunched.state, .skipped)
    }

    // MARK: - Bootstrap

    func testInitialStateIsUnknownUntilBootstrap() {
        XCTAssertEqual(sut.state, .unknown)
    }

    func testBootstrapMovesToSavedWhenKeyAlreadyStored() async throws {
        try await keychain.save("sk-ant-existing", for: .claudeAPIKey)
        await sut.bootstrap()
        XCTAssertEqual(sut.state, .saved)
    }

    func testBootstrapMovesToIdleWithoutStoredKey() async {
        await sut.bootstrap()
        XCTAssertEqual(sut.state, .idle)
    }
}
