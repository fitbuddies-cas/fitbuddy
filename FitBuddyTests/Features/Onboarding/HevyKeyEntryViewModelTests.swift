import XCTest
@testable import FitBuddy

/// Unit tests for `HevyKeyEntryViewModel`. Validation is mocked; Keychain
/// access uses the real `KeychainService` on the simulator (same pattern as
/// `ConsentViewModelTests`), with the Hevy key cleared around each test.
@MainActor
final class HevyKeyEntryViewModelTests: XCTestCase {
    private var keychain: KeychainService!
    private var validator: MockHevyKeyValidator!
    private var sut: HevyKeyEntryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        try await keychain.delete(.hevyAPIKey)
        validator = MockHevyKeyValidator()
        sut = HevyKeyEntryViewModel(validator: validator, keychain: keychain)
    }

    override func tearDown() async throws {
        try await keychain.delete(.hevyAPIKey)
        sut = nil
        validator = nil
        keychain = nil
        try await super.tearDown()
    }

    // MARK: - Input gating

    func testCanConnectRequiresNonEmptyKey() {
        XCTAssertFalse(sut.canConnect)
        sut.apiKey = "   \n"
        XCTAssertFalse(sut.canConnect)
        sut.apiKey = "hv_live_abc"
        XCTAssertTrue(sut.canConnect)
    }

    func testConnectWithEmptyKeyIsNoOp() async throws {
        await sut.bootstrap()
        await sut.connect()
        XCTAssertEqual(sut.state, .idle)
        let receivedKeys = await validator.receivedKeys
        XCTAssertEqual(receivedKeys, [])
    }

    // MARK: - Successful validation (DoD: save only after HTTP 200)

    func testConnectValidatesTrimmedKeyThenSavesAndConnects() async throws {
        sut.apiKey = "  hv_live_abc\n"
        await sut.connect()

        XCTAssertEqual(sut.state, .connected)
        let receivedKeys = await validator.receivedKeys
        XCTAssertEqual(receivedKeys, ["hv_live_abc"])
        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(stored, "hv_live_abc")
    }

    // MARK: - Failed validation (AC3 / DoD: rejected key never stored)

    func testInvalidKeyIsNotStoredAndStateIsInvalidKey() async throws {
        await validator.setResult(.failure(HevyKeyValidationError.invalidKey))
        sut.apiKey = "hv_live_bad"
        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.invalidKey))
        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertNil(stored)
    }

    func testTransportErrorMapsToNetworkFailure() async throws {
        await validator.setResult(.failure(HevyKeyValidationError.transport))
        sut.apiKey = "hv_live_abc"
        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.network))
        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertNil(stored)
    }

    func testUnexpectedStatusMapsToServiceUnavailable() async throws {
        await validator.setResult(.failure(HevyKeyValidationError.unexpectedStatus(503)))
        sut.apiKey = "hv_live_abc"
        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.serviceUnavailable))
        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertNil(stored)
    }

    // MARK: - Recovery

    func testRetryResetsFailureToIdle() async {
        await validator.setResult(.failure(HevyKeyValidationError.invalidKey))
        sut.apiKey = "hv_live_bad"
        await sut.connect()

        sut.retry()
        XCTAssertEqual(sut.state, .idle)
    }

    func testEditingKeyClearsFailure() async {
        await validator.setResult(.failure(HevyKeyValidationError.invalidKey))
        sut.apiKey = "hv_live_bad"
        await sut.connect()

        sut.apiKey = "hv_live_bad2"
        XCTAssertEqual(sut.state, .idle)
    }

    func testConnectSucceedsAfterFailedAttempt() async throws {
        await validator.setResult(.failure(HevyKeyValidationError.invalidKey))
        sut.apiKey = "hv_live_bad"
        await sut.connect()

        await validator.setResult(.success(()))
        sut.apiKey = "hv_live_good"
        await sut.connect()

        XCTAssertEqual(sut.state, .connected)
        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(stored, "hv_live_good")
    }

    // MARK: - Bootstrap

    func testInitialStateIsUnknownUntilBootstrap() {
        XCTAssertEqual(sut.state, .unknown)
    }

    func testBootstrapConnectsWhenKeyAlreadyStored() async throws {
        try await keychain.save("hv_live_existing", for: .hevyAPIKey)
        await sut.bootstrap()
        XCTAssertEqual(sut.state, .connected)
    }

    func testBootstrapMovesToIdleWithoutStoredKey() async {
        await sut.bootstrap()
        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Return-to-step-2 notice (US-8 AC2)

    func testResetWithoutAReasonRaisesNoNotice() {
        sut.apiKey = "stale input"
        sut.reset()

        XCTAssertNil(sut.notice)
        XCTAssertEqual(sut.apiKey, "")
        XCTAssertEqual(sut.state, .idle)
    }

    /// The user did not ask for this screen and never saw the 401, so the
    /// reason has to be on it when they arrive.
    func testResetAnnouncingARejectedKeyRaisesTheNotice() {
        sut.apiKey = "revoked-key"
        sut.reset(announcing: .keyRejected)

        XCTAssertEqual(sut.notice, .keyRejected)
        XCTAssertEqual(sut.apiKey, "")
        XCTAssertEqual(sut.state, .idle)
    }

    /// Typing is not an answer to the notice — a half-entered key does not
    /// make the old one work again, and a banner that vanished on the first
    /// keystroke would take the explanation with it.
    func testNoticeSurvivesEditingTheField() {
        sut.reset(announcing: .keyRejected)
        sut.apiKey = "hv_live_new"

        XCTAssertEqual(sut.notice, .keyRejected)
    }

    func testNoticeSurvivesAFailedAttempt() async {
        sut.reset(announcing: .keyRejected)
        await validator.setResult(.failure(HevyKeyValidationError.invalidKey))
        sut.apiKey = "hv_live_wrong"
        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.invalidKey))
        XCTAssertEqual(sut.notice, .keyRejected)
    }

    /// A key Hevy just accepted is the answer to the notice; leaving it up
    /// would keep announcing a problem that is over.
    func testConnectingClearsTheNotice() async {
        sut.reset(announcing: .keyRejected)
        sut.apiKey = "hv_live_new"
        await sut.connect()

        XCTAssertEqual(sut.state, .connected)
        XCTAssertNil(sut.notice)
    }
}
