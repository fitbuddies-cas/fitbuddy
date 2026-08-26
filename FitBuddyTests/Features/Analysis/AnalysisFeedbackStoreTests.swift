import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisFeedbackStore` (US-3 AC9, #32), each on an isolated
/// `UserDefaults` suite.
final class AnalysisFeedbackStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: AnalysisFeedbackStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = AnalysisFeedbackStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        try await super.tearDown()
    }

    func testNoFeedbackBeforeAnyTap() async {
        let stored = await sut.lastFeedback()
        XCTAssertNil(stored)
        let helpful = await sut.count(of: .helpful)
        XCTAssertEqual(helpful, 0)
    }

    func testRecordRoundTrips() async {
        let date = Date(timeIntervalSince1970: 1_788_000_000)

        await sut.record(.helpful, at: date)

        let stored = await sut.lastFeedback()
        XCTAssertEqual(stored?.feedback, .helpful)
        XCTAssertEqual(stored?.date, date)
        let count = await sut.count(of: .helpful)
        XCTAssertEqual(count, 1)
    }

    /// Changing your mind replaces the verdict — but both taps happened, so
    /// both are counted.
    func testChangedVerdictReplacesTheLastButKeepsBothCounts() async {
        await sut.record(.helpful, at: Date(timeIntervalSince1970: 100))
        await sut.record(.notHelpful, at: Date(timeIntervalSince1970: 200))

        let stored = await sut.lastFeedback()
        XCTAssertEqual(stored?.feedback, .notHelpful)
        XCTAssertEqual(stored?.date, Date(timeIntervalSince1970: 200))
        let helpful = await sut.count(of: .helpful)
        let notHelpful = await sut.count(of: .notHelpful)
        XCTAssertEqual(helpful, 1)
        XCTAssertEqual(notHelpful, 1)
    }

    func testCountsAccumulatePerVerdict() async {
        for index in 0..<3 {
            await sut.record(.helpful, at: Date(timeIntervalSince1970: Double(index)))
        }

        let count = await sut.count(of: .helpful)
        XCTAssertEqual(count, 3)
    }

    func testClearDropsEverything() async {
        await sut.record(.helpful, at: Date(timeIntervalSince1970: 100))

        await sut.clear()

        let stored = await sut.lastFeedback()
        XCTAssertNil(stored)
        let count = await sut.count(of: .helpful)
        XCTAssertEqual(count, 0)
    }

    /// A foreign value under the tally key must restart the count instead of
    /// trapping on a bad cast.
    func testCorruptedTallyIsIgnored() async {
        defaults.set(["helpful": "not a number"], forKey: "fitbuddy.analysis.feedback.tally")

        await sut.record(.helpful, at: Date(timeIntervalSince1970: 100))

        let count = await sut.count(of: .helpful)
        XCTAssertEqual(count, 1)
    }

    /// The epoch is a real timestamp, not "never rated" — `UserDefaults`
    /// returns 0 for a missing key either way, so the verdict key decides.
    func testEpochTimestampIsDistinctFromNeverRated() async {
        await sut.record(.notHelpful, at: Date(timeIntervalSince1970: 0))

        let stored = await sut.lastFeedback()
        XCTAssertEqual(stored?.feedback, .notHelpful)
        XCTAssertEqual(stored?.date, Date(timeIntervalSince1970: 0))
    }
}
