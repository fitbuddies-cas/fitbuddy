import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisFeedbackStore` (US-3 AC9, #32, #117), each on an
/// isolated `UserDefaults` suite.
///
/// Only the tally lives here since #117 — the verdict itself is stored on the
/// analysis it was given for, and `AnalysisResultStoreTests` covers that.
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

    func testNoCountsBeforeAnyTap() async {
        let helpful = await sut.count(of: .helpful)
        let notHelpful = await sut.count(of: .notHelpful)
        XCTAssertEqual(helpful, 0)
        XCTAssertEqual(notHelpful, 0)
    }

    func testRecordCountsTheTap() async {
        await sut.record(.helpful)

        let count = await sut.count(of: .helpful)
        XCTAssertEqual(count, 1)
    }

    /// Changing your mind is two taps, and the tally is about taps — which
    /// recommendation ends up carrying which verdict is the store's business,
    /// not this one's.
    func testAChangedVerdictCountsOnBothSides() async {
        await sut.record(.helpful)
        await sut.record(.notHelpful)

        let helpful = await sut.count(of: .helpful)
        let notHelpful = await sut.count(of: .notHelpful)
        XCTAssertEqual(helpful, 1)
        XCTAssertEqual(notHelpful, 1)
    }

    func testCountsAccumulatePerVerdict() async {
        for _ in 0..<3 {
            await sut.record(.helpful)
        }

        let count = await sut.count(of: .helpful)
        XCTAssertEqual(count, 3)
    }

    func testClearDropsTheTally() async {
        await sut.record(.helpful)

        await sut.clear()

        let count = await sut.count(of: .helpful)
        XCTAssertEqual(count, 0)
    }

    func testTheTallySurvivesANewStoreOnTheSameSuite() async throws {
        await sut.record(.notHelpful)

        // A fresh store on the same suite stands in for the next app launch.
        let reopened = AnalysisFeedbackStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))

        let count = await reopened.count(of: .notHelpful)
        XCTAssertEqual(count, 1)
    }

    /// A foreign value under the tally key must restart the count instead of
    /// trapping on a bad cast.
    func testCorruptedTallyIsIgnored() async {
        defaults.set(["helpful": "not a number"], forKey: "fitbuddy.analysis.feedback.tally")

        await sut.record(.helpful)

        let count = await sut.count(of: .helpful)
        XCTAssertEqual(count, 1)
    }
}
