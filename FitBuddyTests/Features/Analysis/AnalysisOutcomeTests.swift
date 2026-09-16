import XCTest
@testable import FitBuddy

/// How a stored row becomes what the screen renders (US-14 AC6, #177).
final class AnalysisOutcomeTests: XCTestCase {
    func testAStoredReportRendersAsItsCards() {
        let report = ValidatedAnalysisReportFixtures.everyCard
        let snapshot = AnalysisResultSnapshot(
            id: UUID(),
            text: report.summary,
            generatedAt: .now,
            context: AnalysisContext(sessionCount: 12, window: .default),
            report: report
        )

        XCTAssertEqual(AnalysisOutcome(stored: snapshot), .report(report))
    }

    func testARowWithoutAReportRendersAsProse() {
        let snapshot = AnalysisResultSnapshot(
            id: UUID(),
            text: "Old prose.",
            generatedAt: .now,
            context: AnalysisContext(sessionCount: 12, window: .default)
        )

        XCTAssertEqual(AnalysisOutcome(stored: snapshot), .prose("Old prose."))
    }
}
