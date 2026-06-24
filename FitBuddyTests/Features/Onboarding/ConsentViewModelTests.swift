import XCTest
@testable import FitBuddy

/// Unit tests for `ConsentViewModel`. They exercise the real `KeychainService`
/// on the simulator; `setUp`/`tearDown` clear the consent keys so runs stay
/// isolated.
@MainActor
final class ConsentViewModelTests: XCTestCase {
    private var keychain: KeychainService!
    private var sut: ConsentViewModel!

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        try await clearConsentKeys()
        sut = ConsentViewModel(keychain: keychain)
    }

    override func tearDown() async throws {
        try await clearConsentKeys()
        sut = nil
        keychain = nil
        try await super.tearDown()
    }

    private func clearConsentKeys() async throws {
        try await keychain.delete(.consentVersion)
        try await keychain.delete(.consentTimestamp)
    }

    // MARK: - confirm gating

    func testCanConfirmReflectsCheckbox() {
        XCTAssertFalse(sut.canConfirm)
        sut.hasAcceptedCheckbox = true
        XCTAssertTrue(sut.canConfirm)
    }

    func testConfirmWithoutCheckboxIsNoOp() async throws {
        await sut.confirm()
        XCTAssertNotEqual(sut.state, .granted)
        let stored = try await keychain.read(.consentVersion)
        XCTAssertNil(stored)
    }

    // MARK: - persistence

    func testConfirmPersistsVersionAndTimestampAndGrants() async throws {
        sut.hasAcceptedCheckbox = true
        await sut.confirm()

        XCTAssertEqual(sut.state, .granted)
        let version = try await keychain.read(.consentVersion)
        let timestamp = try await keychain.read(.consentTimestamp)
        XCTAssertEqual(version, ConsentViewModel.currentVersion)
        XCTAssertNotNil(timestamp)
    }

    // MARK: - app start / refreshState

    func testRefreshStateRequiredWhenNoConsent() async {
        await sut.refreshState()
        XCTAssertEqual(sut.state, .required)
    }

    func testRefreshStateGrantedAfterConfirmSurvivesNewInstance() async throws {
        sut.hasAcceptedCheckbox = true
        await sut.confirm()

        // Simulate an app restart: a fresh view model reading the same Keychain.
        let restarted = ConsentViewModel(keychain: keychain)
        await restarted.refreshState()
        XCTAssertEqual(restarted.state, .granted)
    }

    func testRefreshStateRequiredOnVersionMismatch() async throws {
        try await keychain.save("v-outdated", for: .consentVersion)
        await sut.refreshState()
        XCTAssertEqual(sut.state, .required)
    }

    // MARK: - bootstrap / fresh-install reset

    func testBootstrapOnFreshInstallClearsPriorConsent() async throws {
        // Prior install granted consent...
        try await keychain.save(ConsentViewModel.currentVersion, for: .consentVersion)

        // ...but a fresh install has no first-launch marker, so bootstrap must
        // wipe the stale consent and re-require it.
        let suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reset = FirstLaunchResetService(defaults: defaults, keychain: keychain)
        let viewModel = ConsentViewModel(keychain: keychain, firstLaunchReset: reset)

        await viewModel.bootstrap()

        XCTAssertEqual(viewModel.state, .required)
        let stored = try await keychain.read(.consentVersion)
        XCTAssertNil(stored)
    }

    func testBootstrapKeepsConsentOnSubsequentLaunch() async throws {
        let suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reset = FirstLaunchResetService(defaults: defaults, keychain: keychain)
        let viewModel = ConsentViewModel(keychain: keychain, firstLaunchReset: reset)

        // First launch: bootstrap sets the marker, then the user grants consent.
        await viewModel.bootstrap()
        viewModel.hasAcceptedCheckbox = true
        await viewModel.confirm()

        // Subsequent launch (marker already set) must not wipe consent.
        await viewModel.bootstrap()
        XCTAssertEqual(viewModel.state, .granted)
    }
}
