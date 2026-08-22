import XCTest
@testable import FitBuddy

/// Unit tests for `OnboardingViewModel`. Keychain access uses the real
/// `KeychainService` on the simulator (same pattern as the step view-model
/// tests), with all keys cleared around each test; UserDefaults-backed
/// state (skip flag, first-launch marker) uses an isolated suite.
@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private var keychain: KeychainService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var validator: MockHevyKeyValidator!

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        for key in KeychainKey.allCases {
            try await keychain.delete(key)
        }
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        validator = MockHevyKeyValidator()
    }

    override func tearDown() async throws {
        for key in KeychainKey.allCases {
            try await keychain.delete(key)
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        validator = nil
        keychain = nil
        try await super.tearDown()
    }

    /// Coordinator whose children share the test's isolated stores. The
    /// first-launch reset marker is pre-set so the consent bootstrap does not
    /// purge Keychain state seeded by the test.
    private func makeSUT(launchArguments: [String] = []) -> OnboardingViewModel {
        defaults.set(true, forKey: "fitbuddy.firstLaunchReset.completed")
        let consent = ConsentViewModel(
            keychain: keychain,
            firstLaunchReset: FirstLaunchResetService(defaults: defaults, keychain: keychain)
        )
        let hevy = HevyKeyEntryViewModel(validator: validator, keychain: keychain)
        let claude = ClaudeKeyEntryViewModel(keychain: keychain, defaults: defaults)
        return OnboardingViewModel(
            keychain: keychain,
            consentViewModel: consent,
            hevyKeyViewModel: hevy,
            claudeKeyViewModel: claude,
            launchArguments: launchArguments
        )
    }

    private func seedConsent() async throws {
        try await keychain.save(ConsentViewModel.currentVersion, for: .consentVersion)
        try await keychain.save("2026-01-01T00:00:00Z", for: .consentTimestamp)
    }

    // MARK: - Bootstrap: resume at the first incomplete step

    func testInitialStepIsLoading() {
        XCTAssertEqual(makeSUT().step, .loading)
    }

    func testBootstrapWithoutConsentStartsAtConsent() async {
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .consent)
    }

    func testBootstrapWithConsentResumesAtHevyStep() async throws {
        try await seedConsent()
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .hevyKey)
    }

    func testBootstrapWithConsentAndHevyKeyResumesAtClaudeStep() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .claudeKey)
    }

    func testBootstrapWithStoredClaudeKeyCompletesOnboarding() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        try await keychain.save("sk-ant-abc", for: .claudeAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .completed)
    }

    func testBootstrapWithSkippedClaudeCompletesOnboarding() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        defaults.set(true, forKey: "fitbuddy.onboarding.claudeKeySkipped")
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .completed)
    }

    // MARK: - Step advancement on user actions

    func testConfirmingConsentAdvancesToHevyStep() async {
        let sut = makeSUT()
        await sut.bootstrap()

        sut.consentViewModel.hasAcceptedCheckbox = true
        await sut.consentViewModel.confirm()

        XCTAssertEqual(sut.step, .hevyKey)
    }

    func testConnectingHevyAdvancesToClaudeStep() async throws {
        try await seedConsent()
        let sut = makeSUT()
        await sut.bootstrap()

        sut.hevyKeyViewModel.apiKey = "hevy-key"
        await sut.hevyKeyViewModel.connect()

        XCTAssertEqual(sut.step, .claudeKey)
    }

    func testSavingClaudeKeyCompletesOnboarding() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()

        sut.claudeKeyViewModel.apiKey = "sk-ant-abc"
        await sut.claudeKeyViewModel.save()

        XCTAssertEqual(sut.step, .completed)
    }

    func testSkippingClaudeCompletesOnboarding() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()

        sut.claudeKeyViewModel.skip()

        XCTAssertEqual(sut.step, .completed)
    }

    /// Regression: re-granting consent (e.g. after a `currentVersion` bump)
    /// must re-resolve the target step from state, not jump straight to
    /// `.hevyKey` as a hardcoded transition would, when Hevy and Claude are
    /// already connected/saved from before.
    func testReGrantingConsentWithDownstreamStepsAlreadyCompleteSkipsToCompleted() async throws {
        try await keychain.save("v-old", for: .consentVersion)
        try await keychain.save("2026-01-01T00:00:00Z", for: .consentTimestamp)
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        try await keychain.save("sk-ant-abc", for: .claudeAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .consent)

        sut.consentViewModel.hasAcceptedCheckbox = true
        await sut.consentViewModel.confirm()

        XCTAssertEqual(sut.step, .completed)
    }

    /// Regression: reconnecting Hevy after a 401 must re-resolve the target
    /// step, not jump straight to `.claudeKey` as a hardcoded transition
    /// would, when Claude is already saved from before.
    func testReconnectingHevyAfterUnauthorizedWithClaudeAlreadySavedSkipsToCompleted() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        try await keychain.save("sk-ant-abc", for: .claudeAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .completed)

        await sut.handleHevyUnauthorized()
        XCTAssertEqual(sut.step, .hevyKey)

        sut.hevyKeyViewModel.apiKey = "new-hevy-key"
        await sut.hevyKeyViewModel.connect()

        XCTAssertEqual(sut.step, .completed)
    }

    // MARK: - Invalid Hevy key (HTTP 401 anywhere in the app)

    func testHevyUnauthorizedDeletesKeyAndReturnsToHevyStep() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        defaults.set(true, forKey: "fitbuddy.onboarding.claudeKeySkipped")
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .completed)

        sut.hevyKeyViewModel.apiKey = "stale input"
        await sut.handleHevyUnauthorized()

        XCTAssertEqual(sut.step, .hevyKey)
        XCTAssertEqual(sut.hevyKeyViewModel.state, .idle)
        XCTAssertEqual(sut.hevyKeyViewModel.apiKey, "")
        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertNil(stored)
    }

    // MARK: - DEBUG skip launch argument

    #if DEBUG
    func testSkipLaunchArgumentBypassesOnboarding() async {
        let sut = makeSUT(launchArguments: [OnboardingViewModel.skipLaunchArgument])
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .completed)
    }
    #endif
}
