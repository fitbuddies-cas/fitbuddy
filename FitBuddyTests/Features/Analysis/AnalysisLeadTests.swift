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
}
