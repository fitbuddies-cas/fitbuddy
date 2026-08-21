import XCTest
@testable import FitBuddy

/// Unit tests for `LLMPriorityStore`, using an isolated `UserDefaults` suite
/// (same pattern as `FirstLaunchResetServiceTests`).
final class LLMPriorityStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: LLMPriorityStore!

    override func setUp() {
        super.setUp()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = LLMPriorityStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        sut = nil
        super.tearDown()
    }

    func testOrderIsEmptyByDefault() {
        XCTAssertEqual(sut.order, [])
    }

    func testSaveAndReadRoundTripPreservesOrder() {
        sut.save([.mistral, .claude, .gemini])
        XCTAssertEqual(sut.order, [.mistral, .claude, .gemini])
    }

    func testOrderSurvivesANewStoreInstance() {
        sut.save([.gemini, .claude])

        // A fresh store on the same defaults simulates a cold start.
        let relaunched = LLMPriorityStore(defaults: defaults)

        XCTAssertEqual(relaunched.order, [.gemini, .claude])
    }

    func testUnknownRawValuesAreDropped() {
        defaults.set(["claude", "openai", "mistral"], forKey: LLMPriorityStore.priorityOrderKey)
        XCTAssertEqual(sut.order, [.claude, .mistral])
    }

    func testClearRemovesTheStoredOrder() {
        sut.save([.claude])
        sut.clear()
        XCTAssertEqual(sut.order, [])
        XCTAssertNil(defaults.stringArray(forKey: LLMPriorityStore.priorityOrderKey))
    }
}
