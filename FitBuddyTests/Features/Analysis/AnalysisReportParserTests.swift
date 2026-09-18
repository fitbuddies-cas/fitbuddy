import XCTest
@testable import FitBuddy

/// The prose fallback of US-14 AC5 (#174): whatever the model sends, the
/// parser produces something to show — or `nil` when showing it would mean
/// showing raw JSON, so the chain can ask the next provider.
final class AnalysisReportParserTests: XCTestCase {
    private let fixture = AnalysisReportFixtures.progressJSON

    // MARK: - Report

    func testDecodesASchemaConformingAnswer() {
        XCTAssertEqual(AnalysisReportParser.event(for: fixture), .report(AnalysisReportFixtures.progress))
    }

    func testDecodesAnAnswerWrappedInACodeFence() {
        let event = AnalysisReportParser.event(for: "```json\n\(fixture)\n```")

        XCTAssertEqual(event, .report(AnalysisReportFixtures.progress))
    }

    func testDecodesAnAnswerInASingleLineFence() {
        let oneLine = fixture.replacingOccurrences(of: "\n", with: " ")

        let event = AnalysisReportParser.event(for: "```json \(oneLine)```")

        XCTAssertEqual(event, .report(AnalysisReportFixtures.progress))
    }

    func testDecodesAnAnswerWithTextBeforeTheFence() {
        let event = AnalysisReportParser.event(for: "Here is your report:\n```json\n\(fixture)\n```\nGood luck!")

        XCTAssertEqual(event, .report(AnalysisReportFixtures.progress))
    }

    /// A report whose summary is blank still gets prose, built from its
    /// headline and one line per card, so the screen always has text to fall
    /// back to. Its missing lead comes from the cards, not the headline the
    /// screen shows right above it.
    func testBuildsTheSummaryFromHeadlineAndCardsWhenItIsBlank() {
        let answer = """
        {"headline": "Recover this week.", "verdict": "recover", "summary": " ",
         "cards": [{"kind": "recovery", "reasoning": "Six sessions in seven days.", "suggestedRestHours": 48},
                   {"kind": "note", "title": "Sleep", "text": "Keep sleep regular."}]}
        """

        guard case .report(let report)? = AnalysisReportParser.event(for: answer) else {
            return XCTFail("expected a report")
        }
        XCTAssertEqual(report.summary, "Recover this week.\nSix sessions in seven days.\nKeep sleep regular.")
        XCTAssertEqual(report.lead, "Six sessions in seven days. Keep sleep regular.")
        XCTAssertEqual(report.verdict, .recover)
        XCTAssertEqual(report.cards.count, 2)
    }

    func testAReportWithNothingToReadIsNoAnswer() {
        let answer = #"{"headline": "", "verdict": "hold", "lead": " ", "summary": "", "cards": []}"#

        XCTAssertNil(AnalysisReportParser.event(for: answer))
    }

    // MARK: - Lead (#170)

    /// A lead-less answer, e.g. one written without the schema, is still a
    /// report: its lead is the first sentences of the summary.
    func testDerivesAMissingLeadFromTheSummary() {
        let answer = """
        {"headline": "Hold steady.", "verdict": "hold",
         "summary": "Two sessions are too few to judge a trend. Keep the current weights. Log another week.",
         "cards": []}
        """

        XCTAssertEqual(
            AnalysisReportParser.event(for: answer),
            .report(AnalysisReport(
                headline: "Hold steady.",
                verdict: .hold,
                lead: "Two sessions are too few to judge a trend. Keep the current weights.",
                cards: [],
                summary: "Two sessions are too few to judge a trend. Keep the current weights. Log another week."
            ))
        )
    }

    func testDerivesABlankLeadFromTheSummary() {
        let answer = """
        {"headline": "Hold steady.", "verdict": "hold", "lead": "  ",
         "summary": "Two sessions are too few to judge a trend.", "cards": []}
        """

        guard case .report(let report)? = AnalysisReportParser.event(for: answer) else {
            return XCTFail("expected a report")
        }
        XCTAssertEqual(report.lead, "Two sessions are too few to judge a trend.")
    }

    /// Zero cards is a valid answer: thin data gets a lead and a summary.
    func testAReportWithoutCardsKeepsItsLead() {
        let answer = """
        {"headline": "Hold steady.", "verdict": "hold", "lead": "Too little data for a change yet.",
         "summary": "Two sessions are too few to judge a trend.", "cards": []}
        """

        guard case .report(let report)? = AnalysisReportParser.event(for: answer) else {
            return XCTFail("expected a report")
        }
        XCTAssertEqual(report.lead, "Too little data for a change yet.")
        XCTAssertTrue(report.cards.isEmpty)
    }

    /// A blank summary is rebuilt with the lead in it; the lead stays as sent.
    func testBuildsTheSummaryFromTheLeadWhenItIsBlank() {
        let answer = """
        {"headline": "Hold steady.", "verdict": "hold", "lead": "Too little data yet.",
         "summary": "", "cards": []}
        """

        guard case .report(let report)? = AnalysisReportParser.event(for: answer) else {
            return XCTFail("expected a report")
        }
        XCTAssertEqual(report.summary, "Hold steady.\nToo little data yet.")
        XCTAssertEqual(report.lead, "Too little data yet.")
    }

    /// A report holding nothing but its headline stays valid, with the
    /// headline as summary — but its lead stays empty instead of repeating
    /// the headline the screen already shows right above it.
    func testAHeadlineOnlyReportGetsNoLead() {
        let answer = #"{"headline": "Hold steady.", "verdict": "hold", "lead": " ", "summary": "", "cards": []}"#

        guard case .report(let report)? = AnalysisReportParser.event(for: answer) else {
            return XCTFail("expected a report")
        }
        XCTAssertEqual(AnalysisLead.resolved("", summary: ""), "")
        XCTAssertEqual(report.summary, "Hold steady.")
        XCTAssertEqual(report.lead, "")
        XCTAssertNotEqual(report.lead, report.headline)
    }

    // MARK: - Summary fallback

    /// A card the schema does not know makes the report unusable, but its
    /// summary is still the model's recommendation.
    func testFallsBackToTheSummaryWhenACardDoesNotDecode() {
        let answer = """
        {"headline": "Go.", "verdict": "progress", "summary": "Run twice this week.",
         "cards": [{"kind": "cardio", "title": "Run"}]}
        """

        XCTAssertEqual(AnalysisReportParser.event(for: answer), .text("Run twice this week."))
    }

    func testFallsBackToTheSummaryWhenAFieldIsMissing() {
        let answer = #"{"verdict": "recover", "summary": "Take two rest days."}"#

        XCTAssertEqual(AnalysisReportParser.event(for: answer), .text("Take two rest days."))
    }

    /// Cut off at the token limit after the summary: the summary is salvaged.
    func testSalvagesACompleteSummaryFromTruncatedJSON() throws {
        let cut = try XCTUnwrap(fixture.range(of: "\"fromKg\""))
        let truncated = String(fixture[..<cut.lowerBound])

        XCTAssertEqual(
            AnalysisReportParser.event(for: truncated),
            .text("Bench press is ready for 62.5 kg. Legs need a second session.")
        )
    }

    func testSalvagesASummaryWithEscapedQuotes() {
        let truncated = #"{"headline": "Go.", "verdict": "progress", "summary": "Keep the \"slow\" tempo.\nThen add 2.5 kg.", "cards": [{"kind": "#

        XCTAssertEqual(
            AnalysisReportParser.event(for: truncated),
            .text("Keep the \"slow\" tempo.\nThen add 2.5 kg.")
        )
    }

    /// Cut off inside the summary: the complete lead before it is salvaged.
    func testSalvagesACompleteLeadWhenTheSummaryIsCutOff() throws {
        let cut = try XCTUnwrap(fixture.range(of: "is ready"))
        let truncated = String(fixture[..<cut.lowerBound])

        XCTAssertEqual(AnalysisReportParser.event(for: truncated), .text("Bench press can go up. Legs are behind."))
    }

    /// Only the top-level key counts: the word in a string, or a `summary` or
    /// `lead` key nested deeper, is not the report's prose.
    func testDoesNotSalvageASummaryFromAnythingButTheTopLevelKey() {
        let truncated = #"{"headline": "summary", "cards": [{"summary": "Nested.", "lead": "Nested."}], "verdict": "progress", "summa"#

        XCTAssertNil(AnalysisReportParser.event(for: truncated))
    }

    // MARK: - No answer

    /// Cut off before the lead is complete: raw JSON is no recommendation.
    func testTruncatedJSONWithoutACompleteSummaryOrLeadIsNoAnswer() throws {
        let cut = try XCTUnwrap(fixture.range(of: "can go up"))
        let truncated = String(fixture[..<cut.lowerBound])

        XCTAssertNil(AnalysisReportParser.event(for: truncated))
    }

    func testJSONWithoutASummaryIsNoAnswer() {
        XCTAssertNil(AnalysisReportParser.event(for: #"{"headline": "Go.", "verdict": "progress", "cards": []}"#))
    }

    func testJSONWithABlankSummaryIsNoAnswer() {
        XCTAssertNil(AnalysisReportParser.event(for: #"{"headline": "Go.", "verdict": "sideways", "cards": [], "summary": "  "}"#))
    }

    func testABlankAnswerIsNoAnswer() {
        XCTAssertNil(AnalysisReportParser.event(for: " \n "))
    }

    // MARK: - Prose

    func testFallsBackToTheTextWhenTheAnswerIsNotJSON() {
        let prose = "Bench press is ready for 62.5 kg."

        XCTAssertEqual(AnalysisReportParser.event(for: "\n\(prose)\n"), .text(prose))
    }
}
