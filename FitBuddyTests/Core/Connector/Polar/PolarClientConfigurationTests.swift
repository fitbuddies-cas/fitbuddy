import XCTest
@testable import FitBuddy

/// Unit tests for `PolarClientConfiguration.loadFromTeamConfig(bundle:)`
/// (issue #155). Builds a throwaway bundle directory per test instead of
/// touching the real (gitignored) `PolarTeamConfig.plist`, so these pass
/// whether or not a developer has filled in real team credentials.
final class PolarClientConfigurationTests: XCTestCase {
    private var bundleDirectory: URL!

    override func setUp() {
        super.setUp()
        bundleDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: bundleDirectory)
        bundleDirectory = nil
        super.tearDown()
    }

    private func writePlist(_ dict: [String: String]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: bundleDirectory.appendingPathComponent("PolarTeamConfig.plist"))
    }

    func testLoadThrowsMissingConfigFileWhenPlistAbsent() {
        let bundle = Bundle(url: bundleDirectory)!

        XCTAssertThrowsError(try PolarClientConfiguration.loadFromTeamConfig(bundle: bundle)) { error in
            XCTAssertEqual(error as? PolarTeamConfigError, .missingConfigFile)
        }
    }

    func testLoadThrowsPlaceholderNotReplacedForUntouchedClientID() throws {
        try writePlist(["PolarClientID": "REPLACE_ME", "PolarRedirectURI": "fitbuddy://polar/callback"])
        let bundle = Bundle(url: bundleDirectory)!

        XCTAssertThrowsError(try PolarClientConfiguration.loadFromTeamConfig(bundle: bundle)) { error in
            XCTAssertEqual(error as? PolarTeamConfigError, .placeholderNotReplaced(key: "PolarClientID"))
        }
    }

    func testLoadThrowsPlaceholderNotReplacedWhenKeyMissing() throws {
        try writePlist(["PolarRedirectURI": "fitbuddy://polar/callback"])
        let bundle = Bundle(url: bundleDirectory)!

        XCTAssertThrowsError(try PolarClientConfiguration.loadFromTeamConfig(bundle: bundle)) { error in
            XCTAssertEqual(error as? PolarTeamConfigError, .placeholderNotReplaced(key: "PolarClientID"))
        }
    }

    func testLoadReturnsConfigurationWithRealValues() throws {
        try writePlist(["PolarClientID": "team-client-id", "PolarRedirectURI": "fitbuddy://polar/callback"])
        let bundle = Bundle(url: bundleDirectory)!

        let configuration = try PolarClientConfiguration.loadFromTeamConfig(bundle: bundle)

        XCTAssertEqual(configuration.clientID, "team-client-id")
        XCTAssertEqual(configuration.redirectURI, "fitbuddy://polar/callback")
        XCTAssertNil(configuration.clientSecret)
    }
}
