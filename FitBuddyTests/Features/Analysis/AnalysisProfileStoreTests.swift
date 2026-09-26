import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisProfileStore` (US-15 AC1, #185): the profile the
/// next analysis starts on survives the screen and the app, and a reset takes
/// it with it.
final class AnalysisProfileStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
    }

    func testNothingIsRememberedBeforeTheFirstChoice() async {
        let store = AnalysisProfileStore(defaults: defaults)
        let remembered = await store.profile
        XCTAssertNil(remembered)
    }

    func testTheChosenProfileIsRememberedForTheNextRun() async {
        let store = AnalysisProfileStore(defaults: defaults)
        await store.save(.overallLoad)

        // A second store over the same defaults is what the next app launch
        // sees.
        let next = AnalysisProfileStore(defaults: defaults)
        let remembered = await next.profile
        XCTAssertEqual(remembered, .overallLoad)
    }

    func testTheLastChoiceReplacesTheOneBeforeIt() async {
        let store = AnalysisProfileStore(defaults: defaults)
        await store.save(.endurance)
        await store.save(.strength)
        let remembered = await store.profile
        XCTAssertEqual(remembered, .strength)
    }

    /// A raw value from a build with a fourth profile: falling back to the
    /// computed default is honest, guessing which one was meant is not.
    func testAnUnknownRawValueReadsAsNothingRemembered() async {
        defaults.set("interference", forKey: AnalysisProfileStore.profileKey)
        let store = AnalysisProfileStore(defaults: defaults)
        let remembered = await store.profile
        XCTAssertNil(remembered)
    }

    func testClearForgetsTheChoice() async {
        let store = AnalysisProfileStore(defaults: defaults)
        await store.save(.endurance)
        await store.clear()
        let remembered = await store.profile
        XCTAssertNil(remembered)
    }
}
