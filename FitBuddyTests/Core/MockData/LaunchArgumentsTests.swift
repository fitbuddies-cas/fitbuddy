import XCTest
@testable import FitBuddy

/// Unit tests for the remembered launch arguments a demo device runs on.
///
/// The seam has two ways to go wrong: forgetting the demo's stubs so a hand-out
/// device asks for a real Hevy key, and remembering them into a developer's
/// plain run. Both are cheap to pin down here and expensive to find on stage.
final class LaunchArgumentsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testPersistsSeamArgumentsWithTheirValues() {
        LaunchArguments.persistIfRequested(
            process: ["app", "-fbStubHevy", "accepts", "-fbSeedMockData", "progression-ready",
                      LaunchArguments.persistLaunchArgument],
            defaults: defaults
        )
        XCTAssertEqual(
            defaults.stringArray(forKey: LaunchArguments.defaultsKey),
            ["-fbStubHevy", "accepts", "-fbSeedMockData", "progression-ready"]
        )
    }

    func testNeverPersistsTheResetOrPersistFlagThemselves() {
        LaunchArguments.persistIfRequested(
            process: ["app", "-fbResetState", "-fbSkipOnboarding", LaunchArguments.persistLaunchArgument],
            defaults: defaults
        )
        XCTAssertEqual(defaults.stringArray(forKey: LaunchArguments.defaultsKey), ["-fbSkipOnboarding"])
    }

    func testSeamLaunchWithoutTheFlagForgetsRememberedArguments() {
        defaults.set(["-fbStubHevy", "accepts"], forKey: LaunchArguments.defaultsKey)
        LaunchArguments.persistIfRequested(process: ["app", "-fbSeedMockData", "plateau"], defaults: defaults)
        XCTAssertNil(defaults.stringArray(forKey: LaunchArguments.defaultsKey))
    }

    func testPlainLaunchLeavesRememberedArgumentsAlone() {
        defaults.set(["-fbStubHevy", "accepts"], forKey: LaunchArguments.defaultsKey)
        LaunchArguments.persistIfRequested(process: ["app"], defaults: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: LaunchArguments.defaultsKey), ["-fbStubHevy", "accepts"])
    }

    func testPlainLaunchResolvesToRememberedArguments() {
        defaults.set(["-fbStubHevy", "accepts"], forKey: LaunchArguments.defaultsKey)
        XCTAssertEqual(
            LaunchArguments.resolve(process: ["app"], defaults: defaults),
            ["app", "-fbStubHevy", "accepts"]
        )
    }

    func testSeamLaunchIgnoresRememberedArguments() {
        defaults.set(["-fbStubHevy", "accepts"], forKey: LaunchArguments.defaultsKey)
        XCTAssertEqual(
            LaunchArguments.resolve(process: ["app", "-fbSeedMockData", "plateau"], defaults: defaults),
            ["app", "-fbSeedMockData", "plateau"]
        )
    }

    func testPlainLaunchWithNothingRememberedIsUnchanged() {
        XCTAssertEqual(LaunchArguments.resolve(process: ["app"], defaults: defaults), ["app"])
    }
}
