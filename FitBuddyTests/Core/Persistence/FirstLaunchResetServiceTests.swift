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
}
