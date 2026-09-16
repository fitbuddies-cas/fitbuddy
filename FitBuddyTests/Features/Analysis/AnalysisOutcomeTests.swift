import XCTest
@testable import FitBuddy

/// How a stored row becomes what the screen renders (US-14 AC6, #177).
final class AnalysisOutcomeTests: XCTestCase {
    func testAStoredReportRendersAsItsCards() {
        let report = AnalysisReportFactory.validatedEveryCard
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

    /// A stored report whose cards are all gone renders its summary (#177).
    func testAStoredReportWithoutCardsRendersItsSummary() {
        let report = ValidatedAnalysisReport(headline: "H", verdict: .hold, cards: [], summary: "Summary.")
        let snapshot = AnalysisResultSnapshot(
            id: UUID(),
            text: "Stored text.",
            generatedAt: .now,
            context: AnalysisContext(sessionCount: 12, window: .default),
            report: report
        )

        XCTAssertEqual(AnalysisOutcome(stored: snapshot), .prose("Summary."))
    }

    func testAValidatedReportWithCardsStaysAReport() {
        let report = AnalysisReportFactory.validatedEveryCard
        XCTAssertEqual(AnalysisOutcome(validated: report), .report(report))
    }

    func testAValidatedReportWithoutCardsBecomesProse() {
        let report = ValidatedAnalysisReport(headline: "H", verdict: .progress, cards: [], summary: "Summary.")
        XCTAssertEqual(AnalysisOutcome(validated: report), .prose("Summary."))
    }
}
