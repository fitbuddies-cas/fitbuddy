import XCTest
@testable import FitBuddy

/// Unit tests for `ClaudeKeyEntryViewModel`. Keychain access uses the real
/// `KeychainService` on the simulator (same pattern as
/// `HevyKeyEntryViewModelTests`), with the Claude key cleared around each test.
@MainActor
final class ClaudeKeyEntryViewModelTests: XCTestCase {
    private var keychain: KeychainService!
    private var sut: ClaudeKeyEntryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        try await keychain.delete(.claudeAPIKey)
        sut = ClaudeKeyEntryViewModel(keychain: keychain)
    }

    override func tearDown() async throws {
        try await keychain.delete(.claudeAPIKey)
        sut = nil
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

    // MARK: - Recovery

    func testRetryIsNoOpWhenNotFailed() async {
        await sut.bootstrap()
        sut.retry()
        XCTAssertEqual(sut.state, .idle)
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
