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

    func testOrderIsEmptyByDefault() async {
        let order = await sut.order
        XCTAssertEqual(order, [])
    }

    func testSaveAndReadRoundTripPreservesOrder() async {
        await sut.save([.mistral, .claude, .gemini])
        let order = await sut.order
        XCTAssertEqual(order, [.mistral, .claude, .gemini])
    }

    func testOrderSurvivesANewStoreInstance() async {
        await sut.save([.gemini, .claude])

        // A fresh store on the same defaults simulates a cold start.
        let relaunched = LLMPriorityStore(defaults: defaults)

        let order = await relaunched.order
        XCTAssertEqual(order, [.gemini, .claude])
    }

    func testUnknownRawValuesAreDropped() async {
        defaults.set(["claude", "openai", "mistral"], forKey: LLMPriorityStore.priorityOrderKey)
        let order = await sut.order
        XCTAssertEqual(order, [.claude, .mistral])
    }

    func testClearRemovesTheStoredOrder() async {
        await sut.save([.claude])
        await sut.clear()
        let order = await sut.order
        XCTAssertEqual(order, [])
        XCTAssertNil(defaults.stringArray(forKey: LLMPriorityStore.priorityOrderKey))
    }
}
