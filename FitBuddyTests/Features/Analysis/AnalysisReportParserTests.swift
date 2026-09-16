import XCTest
@testable import FitBuddy

/// The prose fallback of US-14 AC5 (#174): whatever the model sends, the
/// parser produces something to show, never an error.
final class AnalysisReportParserTests: XCTestCase {
    func testDecodesASchemaConformingAnswer() {
        let event = AnalysisReportParser.event(for: AnalysisReportFixtures.progressJSON)

        XCTAssertEqual(event, .report(AnalysisReportFixtures.progress))
    }

    func testDecodesAnAnswerWrappedInACodeFence() {
        let event = AnalysisReportParser.event(for: "```json\n\(AnalysisReportFixtures.progressJSON)\n```")

        XCTAssertEqual(event, .report(AnalysisReportFixtures.progress))
    }

    func testFallsBackToTheRawTextWhenTheAnswerIsNotJSON() {
        let prose = "Bench press is ready for 62.5 kg."

        XCTAssertEqual(AnalysisReportParser.event(for: prose), .text(prose))
    }

    /// A card the schema does not know makes the report unusable, but its
    /// summary is still the model's recommendation.
    func testFallsBackToTheSummaryWhenACardDoesNotDecode() {
        let answer = """
        {"headline": "Go.", "verdict": "progress",
         "cards": [{"kind": "cardio", "title": "Run"}],
         "summary": "Run twice this week."}
        """

        XCTAssertEqual(AnalysisReportParser.event(for: answer), .text("Run twice this week."))
    }

    func testFallsBackToTheSummaryWhenAFieldIsMissing() {
        let answer = #"{"verdict": "recover", "summary": "Take two rest days."}"#

        XCTAssertEqual(AnalysisReportParser.event(for: answer), .text("Take two rest days."))
    }

    func testFallsBackToTheRawTextWhenTheSummaryIsMissing() {
        let answer = #"{"headline": "Go.", "verdict": "progress", "cards": []}"#

        XCTAssertEqual(AnalysisReportParser.event(for: answer), .text(answer))
    }

    func testFallsBackToTheRawTextWhenTheSummaryIsBlank() {
        let answer = #"{"headline": "Go.", "verdict": "sideways", "cards": [], "summary": "  "}"#

        XCTAssertEqual(AnalysisReportParser.event(for: answer), .text(answer))
    }

    /// An answer cut off at the token limit is no JSON document at all.
    func testFallsBackToTheRawTextForTruncatedJSON() {
        let truncated = String(AnalysisReportFixtures.progressJSON.prefix(120))

        XCTAssertEqual(AnalysisReportParser.event(for: truncated), .text(truncated))
    }
}
