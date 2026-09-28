import XCTest
@testable import FitBuddy

/// The verdict headline copy (US-14 AC1, #177).
final class AnalysisHeadlineTests: XCTestCase {
    func testEachVerdictHasItsCopy() {
        XCTAssertEqual(AnalysisHeadline.text(for: .progress), "You're ready to progress.")
        XCTAssertEqual(AnalysisHeadline.text(for: .recover), "Recover this week.")
        XCTAssertEqual(AnalysisHeadline.text(for: .hold), "Hold steady this week.")
        // ADR-014 §6, word for word.
        XCTAssertEqual(AnalysisHeadline.text(for: .insufficientData), "Not enough data to judge.")
    }

    /// Every verdict has copy, so a case added without one fails here rather
    /// than reaching the screen blank.
    func testNoVerdictIsWithoutCopy() {
        for verdict in AnalysisVerdict.allCases {
            XCTAssertFalse(AnalysisHeadline.text(for: verdict).isEmpty, "\(verdict)")
        }
    }

    /// Two lines, broken where design 3.4/3.5 breaks them.
    func testTheHeadlineBreaksIntoTwoLines() {
        XCTAssertEqual(AnalysisHeadline.lines(for: .progress), ["You're ready", "to progress."])
        XCTAssertEqual(AnalysisHeadline.lines(for: .recover), ["Recover", "this week."])
        for verdict in AnalysisVerdict.allCases {
            XCTAssertEqual(AnalysisHeadline.lines(for: verdict).count, 2, "\(verdict)")
        }
    }
}
