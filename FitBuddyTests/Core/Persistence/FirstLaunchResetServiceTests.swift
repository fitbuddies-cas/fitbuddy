import XCTest
@testable import FitBuddy

/// Unit tests for `FirstLaunchResetService`. Each test uses an isolated
/// `UserDefaults` suite and the real Keychain on the simulator.
final class FirstLaunchResetServiceTests: XCTestCase {
    private var keychain: KeychainService!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        try await clearConsentKeys()
    }

    override func tearDown() async throws {
        try await clearConsentKeys()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        keychain = nil
        try await super.tearDown()
    }

    private func clearConsentKeys() async throws {
        for key in KeychainKey.allCases {
            try await keychain.delete(key)
        }
    }

    func testFirstLaunchPurgesKeychain() async throws {
        try await keychain.save("stale", for: .consentVersion)
        let sut = FirstLaunchResetService(defaults: defaults, keychain: keychain)

        try await sut.resetIfFirstLaunch()

        let value = try await keychain.read(.consentVersion)
        XCTAssertNil(value)
    }

    func testSubsequentLaunchDoesNotPurge() async throws {
        let sut = FirstLaunchResetService(defaults: defaults, keychain: keychain)

        // First launch sets the marker and purges (nothing to purge yet).
        try await sut.resetIfFirstLaunch()

        // A value saved after the first launch must survive later launches.
        try await keychain.save("kept", for: .consentVersion)
        try await sut.resetIfFirstLaunch()

        let value = try await keychain.read(.consentVersion)
        XCTAssertEqual(value, "kept")
    }

    // MARK: - Forced reset (#120)

    /// The UI tests' precondition: a launch that has to start from nothing,
    /// however many launches came before it.
    func testForcedResetPurgesEvenWithTheMarkerSet() async throws {
        let sut = makeForcedSUT()
        try await sut.resetIfFirstLaunch()
        try await keychain.save("stale", for: .consentVersion)

        try await sut.resetIfFirstLaunch()

        let value = try await keychain.read(.consentVersion)
        XCTAssertNil(value)
    }

    /// A real first launch starts with empty `UserDefaults`; a forced one does
    /// not. Without clearing the domain the step-3 skip marker would survive,
    /// and a UI test walking onboarding would find step 3 already answered.
    func testForcedResetClearsTheDefaultsDomain() async throws {
        defaults.set(true, forKey: LLMKeysSkipStore.skippedKey)
        let sut = makeForcedSUT()

        try await sut.resetIfFirstLaunch()

        XCTAssertFalse(defaults.bool(forKey: LLMKeysSkipStore.skippedKey))
    }

    /// The marker is written after the domain is cleared, so the launch that
    /// follows a forced reset behaves like any later launch.
    func testForcedResetLeavesTheMarkerSetBehind() async throws {
        let sut = makeForcedSUT()
        try await sut.resetIfFirstLaunch()

        try await keychain.save("kept", for: .consentVersion)
        let plain = FirstLaunchResetService(defaults: defaults, keychain: keychain, launchArguments: [])
        try await plain.resetIfFirstLaunch()

        let value = try await keychain.read(.consentVersion)
        XCTAssertEqual(value, "kept")
    }

    /// The argument is the only thing that forces it — an ordinary launch is
    /// unaffected.
    func testWithoutTheArgumentNothingIsForced() async throws {
        let sut = FirstLaunchResetService(defaults: defaults, keychain: keychain, launchArguments: [])
        try await sut.resetIfFirstLaunch()
        try await keychain.save("kept", for: .consentVersion)

        try await sut.resetIfFirstLaunch()

        let value = try await keychain.read(.consentVersion)
        XCTAssertEqual(value, "kept")
    }

    private func makeForcedSUT() -> FirstLaunchResetService {
        FirstLaunchResetService(
            defaults: defaults,
            keychain: keychain,
            launchArguments: [FirstLaunchResetService.resetLaunchArgument],
            domainName: suiteName
        )
    }
}
