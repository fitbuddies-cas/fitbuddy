import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisContext` (US-6, #36): the thin-data rule of AC2 and
/// the source list of AC1.
final class AnalysisContextTests: XCTestCase {
    private func context(sessions: Int, weeks: Int = 4) -> AnalysisContext {
        AnalysisContext(sessionCount: sessions, window: AnalysisWindow(weeks: weeks))
    }

    /// The boundary itself, from both sides: US-6 AC2 says "fewer than 5", so
    /// five sessions is the first count that is no longer thin.
    func testThinDataEndsAtTheThreshold() {
        XCTAssertTrue(context(sessions: AnalysisContext.thinDataThreshold - 1).isThin)
        XCTAssertFalse(context(sessions: AnalysisContext.thinDataThreshold).isThin)
    }

    /// A window with nothing in it never reaches the view — the run fails with
    /// `.noTrainingData` first — but the rule must not invert if it ever does.
    func testEmptyWindowIsThin() {
        XCTAssertTrue(context(sessions: 0).isThin)
    }

    /// The widened window of #87 does not change the rule: four sessions
    /// spread over 13 weeks are thinner still, not less thin.
    func testThinDataRuleIgnoresTheWindowLength() {
        XCTAssertTrue(context(sessions: 4, weeks: 13).isThin)
        XCTAssertFalse(context(sessions: 12, weeks: 13).isThin)
    }

    /// v0 has exactly one connector, and the context line must not name a
    /// source the app never read (US-6 AC1).
    func testHevyIsTheOnlySourceInV0() {
        XCTAssertEqual(context(sessions: 12).sources, ["Hevy"])
    }
}
