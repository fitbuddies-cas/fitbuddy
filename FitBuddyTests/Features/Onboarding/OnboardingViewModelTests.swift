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
        let llmKeys = LLMKeysViewModel(keychain: keychain, defaults: defaults)
        let profileStore = TrainingProfileStore(defaults: defaults)
        return OnboardingViewModel(
            keychain: keychain,
            consentViewModel: consent,
            hevyKeyViewModel: hevy,
            llmKeysViewModel: llmKeys,
            trainingProfileViewModel: TrainingProfileViewModel(store: profileStore),
            trainingProfileStore: profileStore,
            launchArguments: launchArguments
        )
    }

    // MARK: - Step 4: training profile (US-13, #190)

    /// A fresh install walks all four steps: the last one is the profile, not
    /// the dashboard.
    func testAFreshInstallReachesTheProfileStep() async {
        let sut = makeSUT()
        await sut.bootstrap()
        await grantConsent(sut)
        await connectHevyKey(sut)

        await sut.llmKeysViewModel.skip()

        XCTAssertEqual(sut.step, .trainingProfile)
    }

    func testAnsweringTheProfileCompletesOnboarding() async {
        let sut = makeSUT()
        await sut.bootstrap()
        await grantConsent(sut)
        await connectHevyKey(sut)
        await sut.llmKeysViewModel.skip()

        sut.trainingProfileViewModel.goal = .improveEndurance
        await sut.trainingProfileViewModel.save()

        XCTAssertEqual(sut.step, .completed)
    }

    func testSkippingTheProfileCompletesOnboarding() async {
        let sut = makeSUT()
        await sut.bootstrap()
        await grantConsent(sut)
        await connectHevyKey(sut)
        await sut.llmKeysViewModel.skip()

        await sut.trainingProfileViewModel.skip()

        XCTAssertEqual(sut.step, .completed)
    }

    /// A user who quits mid-step-4 comes back to it, like every other step.
    func testAnUndecidedProfileResumesAtStepFour() async {
        let first = makeSUT()
        await first.bootstrap()
        await grantConsent(first)
        await connectHevyKey(first)
        await first.llmKeysViewModel.skip()
        XCTAssertEqual(first.step, .trainingProfile)

        let second = makeSUT()
        await second.bootstrap()

        XCTAssertEqual(second.step, .trainingProfile)
    }

    // MARK: - Installs that predate the step

    /// The case the whole migration exists for: someone who finished the
    /// three-step onboarding before step 4 existed must not be sent back into
    /// it — they reach the profile through Settings (#189).
    func testAnInstallThatWasAlreadyCompleteIsNotSentBack() async {
        // Onboarding as it stood before US-13, on an install that never saw
        // the new step.
        try? await keychain.save(ConsentViewModel.currentVersion, for: .consentVersion)
        try? await keychain.save("2026-01-01T00:00:00Z", for: .consentTimestamp)
        try? await keychain.save("hv_live_abc", for: .hevyAPIKey)
        defaults.set(true, forKey: LLMKeysSkipStore.skippedKey)

        let sut = makeSUT()
        await sut.bootstrap()

        XCTAssertEqual(sut.step, .completed)
        // Recorded as settled, so the next launch does not reconsider.
        let decided = await TrainingProfileStore(defaults: defaults).isDecided
        XCTAssertTrue(decided)
    }

    /// The trap the marker avoids: a *new* user who quits right after step 3
    /// looks "already complete" on the next launch. Checking completeness
    /// alone would excuse them and never ask — but their first bootstrap had
    /// nothing finished, so the marker was already set without the excuse.
    func testANewUserWhoQuitsAfterStepThreeIsStillAsked() async {
        let first = makeSUT()
        await first.bootstrap()
        await grantConsent(first)
        await connectHevyKey(first)
        await first.llmKeysViewModel.skip()

        let second = makeSUT()
        await second.bootstrap()

        XCTAssertEqual(second.step, .trainingProfile)
    }

    private func grantConsent(_ sut: OnboardingViewModel) async {
        sut.consentViewModel.hasAcceptedCheckbox = true
        await sut.consentViewModel.confirm()
    }

    private func connectHevyKey(_ sut: OnboardingViewModel) async {
        await validator.setResult(.success(()))
        sut.hevyKeyViewModel.apiKey = "hv_live_abc"
        await sut.hevyKeyViewModel.connect()
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

    func testBootstrapWithConsentAndHevyKeyResumesAtLLMStep() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .llmKeys)
    }

    func testBootstrapWithStoredLLMKeyCompletesOnboarding() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        try await keychain.save("sk-ant-abc", for: .claudeAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .completed)
    }

    func testBootstrapWithSkippedLLMStepCompletesOnboarding() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        defaults.set(true, forKey: "fitbuddy.onboarding.llmKeysSkipped")
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

    func testConnectingHevyAdvancesToLLMStep() async throws {
        try await seedConsent()
        let sut = makeSUT()
        await sut.bootstrap()

        sut.hevyKeyViewModel.apiKey = "hevy-key"
        await sut.hevyKeyViewModel.connect()

        XCTAssertEqual(sut.step, .llmKeys)
    }

    /// Step 3 no longer ends the flow: the profile step follows it (US-13).
    func testSavingLLMKeyAdvancesToTheProfileStep() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()

        sut.llmKeysViewModel.slots = [LLMKeySlot(provider: .claude, key: "sk-ant-abc")]
        await sut.llmKeysViewModel.save()

        XCTAssertEqual(sut.step, .trainingProfile)
    }

    func testSkippingLLMStepAdvancesToTheProfileStep() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()

        await sut.llmKeysViewModel.skip()

        XCTAssertEqual(sut.step, .trainingProfile)
    }

    /// Regression: re-granting consent (e.g. after a `currentVersion` bump)
    /// must re-resolve the target step from state, not jump straight to
    /// `.hevyKey` as a hardcoded transition would, when Hevy and an LLM key
    /// are already connected/saved from before.
    ///
    /// The bootstrap here finds consent outstanding, so the install is not
    /// excused from step 4 — which makes `.completed` the wrong expectation
    /// now: the profile is still unanswered.
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

        XCTAssertEqual(sut.step, .trainingProfile)
    }

    /// Regression: reconnecting Hevy after a 401 must re-resolve the target
    /// step, not jump straight to `.llmKeys` as a hardcoded transition
    /// would, when an LLM key is already saved from before.
    func testReconnectingHevyAfterUnauthorizedWithLLMKeyAlreadySavedSkipsToCompleted() async throws {
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
        defaults.set(true, forKey: "fitbuddy.onboarding.llmKeysSkipped")
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

    /// US-8 AC2: the user is moved off a working dashboard by a 401 they never
    /// saw. Arriving on step 2 with no explanation is the silent failure the
    /// AC rules out, so the reason travels with them.
    func testHevyUnauthorizedAnnouncesWhyTheUserIsBackOnStepTwo() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        defaults.set(true, forKey: "fitbuddy.onboarding.llmKeysSkipped")
        let sut = makeSUT()
        await sut.bootstrap()

        await sut.handleHevyUnauthorized()

        XCTAssertEqual(sut.hevyKeyViewModel.notice, .keyRejected)
    }

    /// Deleting the key in Settings lands on the same screen and says nothing:
    /// the user pressed the button and is looking at the result of it.
    func testDeletingTheKeyReturnsToStepTwoWithoutANotice() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        defaults.set(true, forKey: "fitbuddy.onboarding.llmKeysSkipped")
        let sut = makeSUT()
        await sut.bootstrap()

        await sut.handleHevyKeyDeleted()

        XCTAssertEqual(sut.step, .hevyKey)
        XCTAssertNil(sut.hevyKeyViewModel.notice)
        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertNil(stored)
    }

    /// Reconnecting is the end of the notice: it explains a key that no longer
    /// exists, and the new one has just been accepted.
    func testReconnectingAfterUnauthorizedClearsTheNotice() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        defaults.set(true, forKey: "fitbuddy.onboarding.llmKeysSkipped")
        let sut = makeSUT()
        await sut.bootstrap()
        await sut.handleHevyUnauthorized()
        XCTAssertEqual(sut.hevyKeyViewModel.notice, .keyRejected)

        sut.hevyKeyViewModel.apiKey = "new-hevy-key"
        await sut.hevyKeyViewModel.connect()

        XCTAssertEqual(sut.step, .completed)
        XCTAssertNil(sut.hevyKeyViewModel.notice)
    }

    /// Wiping everything restarts at consent, so a notice about a Hevy key
    /// from the previous install would be waiting two steps later.
    func testDataResetClearsTheNotice() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()
        await sut.handleHevyUnauthorized()

        sut.handleDataReset()

        XCTAssertEqual(sut.step, .consent)
        XCTAssertNil(sut.hevyKeyViewModel.notice)
    }

    // MARK: - Delete all data (#83)

    func testDataResetReturnsToConsentAndClearsTheChildren() async throws {
        try await seedConsent()
        try await keychain.save("hevy-key", for: .hevyAPIKey)
        try await keychain.save("sk-ant-abc", for: .claudeAPIKey)
        let sut = makeSUT()
        await sut.bootstrap()
        XCTAssertEqual(sut.step, .completed)
        sut.hevyKeyViewModel.apiKey = "stale input"
        sut.llmKeysViewModel.slots[0].key = "stale key"

        sut.handleDataReset()

        XCTAssertEqual(sut.step, .consent)
        XCTAssertEqual(sut.consentViewModel.state, .required)
        XCTAssertFalse(sut.consentViewModel.hasAcceptedCheckbox)
        XCTAssertEqual(sut.hevyKeyViewModel.state, .idle)
        XCTAssertEqual(sut.hevyKeyViewModel.apiKey, "")
        XCTAssertEqual(sut.llmKeysViewModel.state, .idle)
        XCTAssertEqual(sut.llmKeysViewModel.slots.map(\.key), [""])
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
