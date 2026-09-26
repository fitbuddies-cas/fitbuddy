import XCTest
@testable import FitBuddy

/// Unit tests for `EffortHintStore` (#245, US-18 AC6): the flag that makes the
/// effort hint a one-time hint.
final class EffortHintStoreTests: XCTestCase {
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

    func testAFreshInstallHasNotShownTheHint() async {
        let shown = await EffortHintStore(defaults: defaults).hasShownHint
        XCTAssertFalse(shown)
    }

    /// Persisted, not held in memory: a new store over the same defaults — an
    /// app restart — still knows.
    func testMarkingTheHintShownSurvivesANewStore() async {
        await EffortHintStore(defaults: defaults).markShown()

        let shown = await EffortHintStore(defaults: defaults).hasShownHint
        XCTAssertTrue(shown)
    }

    func testClearForgetsTheHint() async {
        let store = EffortHintStore(defaults: defaults)
        await store.markShown()

        await store.clear()

        let shown = await store.hasShownHint
        XCTAssertFalse(shown)
    }
}
