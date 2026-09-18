import XCTest
@testable import FitBuddy

/// The lead rebuilt from a summary when an answer or a stored report has none
/// (#170).
final class AnalysisLeadTests: XCTestCase {
    func testTakesTheFirstTwoSentences() {
        let summary = "Bench press is ready for 62.5 kg. Legs need a second session. Sleep well."

        XCTAssertEqual(
            AnalysisLead.derived(from: summary),
            "Bench press is ready for 62.5 kg. Legs need a second session."
        )
    }

    func testASingleSentenceIsTheWholeLead() {
        XCTAssertEqual(AnalysisLead.derived(from: "  Keep the current weights.\n"), "Keep the current weights.")
    }

    func testStopsBeforeASecondSentenceThatBreaksTheWordLimit() {
        let first = "Keep the current weights."
        let second = "Then " + Array(repeating: "more", count: AnalysisLead.maxWords).joined(separator: " ") + "."

        XCTAssertEqual(AnalysisLead.derived(from: "\(first) \(second)"), first)
    }

    func testCutsAFirstSentenceLongerThanTheWordLimit() {
        let words = (1...80).map { "w\($0)" }
        let summary = words.joined(separator: " ")

        let lead = AnalysisLead.derived(from: summary)

        XCTAssertEqual(lead, words.prefix(AnalysisLead.maxWords).joined(separator: " ") + "…")
    }

    func testABlankSummaryHasNoLead() {
        XCTAssertEqual(AnalysisLead.derived(from: " \n "), "")
    }

    func testResolvedKeepsALeadWithText() {
        XCTAssertEqual(AnalysisLead.resolved("Own lead.", summary: "Other text."), "Own lead.")
    }

    func testResolvedDerivesABlankLead() {
        XCTAssertEqual(AnalysisLead.resolved("  ", summary: "Other text. More."), "Other text. More.")
    }

    // MARK: - Markdown and abbreviations (#170 review)

    /// The shape of the thin sample: an opening paragraph, a bold heading, a
    /// paragraph with a line break, a list.
    func testSkipsHeadingsAndListsOfAStructuredSummary() {
        let summary = """
            You logged two sessions in the last four weeks, both upper body.

            **What the data shows**
            Bench press and rows each appear once, at the same weights as \
            before.

            - Keep your current weights for the next sessions
            - Log two to three sessions a week so a trend can show
            """

        XCTAssertEqual(
            AnalysisLead.derived(from: summary),
            "You logged two sessions in the last four weeks, both upper body. Bench press and rows each appear once, at the same weights as before."
        )
    }

    func testStripsEmphasisMarkers() {
        XCTAssertEqual(
            AnalysisLead.derived(from: "**Bench press** is ready for *62.5 kg*. Legs lag."),
            "Bench press is ready for 62.5 kg. Legs lag."
        )
    }

    func testANumberedListDoesNotLeakItsMarkers() {
        let summary = """
            **Plan**
            1. Add 2.5 kg on bench.
            2. Keep squats where they are.

            Legs need a second session.
            """

        XCTAssertEqual(AnalysisLead.derived(from: summary), "Legs need a second session.")
    }

    func testASummaryThatIsOnlyAListFallsBackToItsItems() {
        let summary = "- Add 2.5 kg on bench.\n- Keep squats where they are.\n- Sleep well."

        XCTAssertEqual(AnalysisLead.derived(from: summary), "Add 2.5 kg on bench. Keep squats where they are.")
    }

    func testAbbreviationsDoNotEndASentence() {
        let summary = "Bench press moved approx. 5 % in four weeks, e.g. from 60 to 62.5 kg. Legs lag behind. Rest well."

        XCTAssertEqual(
            AnalysisLead.derived(from: summary),
            "Bench press moved approx. 5 % in four weeks, e.g. from 60 to 62.5 kg. Legs lag behind."
        )
    }

    func testAHeadingOnlySummaryHasNoLead() {
        XCTAssertEqual(AnalysisLead.derived(from: "**Summary**"), "")
    }
}
