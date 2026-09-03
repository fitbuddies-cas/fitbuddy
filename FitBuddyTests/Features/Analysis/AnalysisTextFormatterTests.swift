import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisTextFormatter` (#117): the structure the providers
/// put into their answers, and what is left of it on screen.
final class AnalysisTextFormatterTests: XCTestCase {
    // MARK: - Helpers

    /// The blocks reduced to `("heading" | "paragraph" | "bullet", text)`, so a
    /// test asserts what the screen renders rather than how `AttributedString`
    /// spells it.
    private func rendered(_ raw: String) -> [(kind: String, text: String)] {
        AnalysisTextFormatter.blocks(from: raw).map { block in
            switch block {
            case .heading(let title):
                return ("heading", title)
            case .paragraph(let text):
                return ("paragraph", String(text.characters))
            case .bullet(let item):
                return ("bullet", String(item.characters))
            }
        }
    }

    private func assertRenders(
        _ raw: String,
        as expected: [(kind: String, text: String)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = rendered(raw)
        XCTAssertEqual(actual.map(\.kind), expected.map(\.kind), file: file, line: line)
        XCTAssertEqual(actual.map(\.text), expected.map(\.text), file: file, line: line)
    }

    // MARK: - Headings

    func testABoldOnlyLineBecomesAHeadingWithoutItsMarkers() {
        assertRenders(
            "**Progressive Overload**\nAdd 2.5 kg on bench.",
            as: [("heading", "Progressive Overload"), ("paragraph", "Add 2.5 kg on bench.")]
        )
    }

    func testATrailingColonBelongsToTheMarkers() {
        assertRenders("**Progressive Overload:**", as: [("heading", "Progressive Overload")])
        assertRenders("**Progressive Overload**:", as: [("heading", "Progressive Overload")])
    }

    func testHashLinesBecomeTheSameHeading() {
        assertRenders("# Volume", as: [("heading", "Volume")])
        assertRenders("## Volume", as: [("heading", "Volume")])
    }

    /// A sentence that merely starts bold is a sentence, not a title —
    /// otherwise half the recommendation would be set as headings.
    func testALineThatOnlyStartsBoldStaysAParagraph() {
        assertRenders(
            "**Bench press** has sat at 60 kg.",
            as: [("paragraph", "Bench press has sat at 60 kg.")]
        )
    }

    // MARK: - Bullets

    func testDashBulletsLoseTheirMarker() {
        assertRenders(
            "- Add 2.5 kg\n- Keep the reps",
            as: [("bullet", "Add 2.5 kg"), ("bullet", "Keep the reps")]
        )
    }

    func testAsteriskAndNumberedBulletsAreTheSameList() {
        assertRenders("* Add 2.5 kg", as: [("bullet", "Add 2.5 kg")])
        assertRenders("1. Add 2.5 kg", as: [("bullet", "Add 2.5 kg")])
        assertRenders("2) Keep the reps", as: [("bullet", "Keep the reps")])
    }

    // MARK: - Prose

    /// The case the prompt actually asks for: no markers at all, and nothing
    /// may be dropped or re-styled because of it.
    func testProseWithoutAnyMarkerBecomesParagraphs() {
        assertRenders(
            "You trained 14 times.\n\nBench press has stalled.",
            as: [("paragraph", "You trained 14 times."), ("paragraph", "Bench press has stalled.")]
        )
    }

    func testWrappedLinesJoinIntoOneParagraph() {
        assertRenders(
            "You trained 14 times,\nwith chest carrying most of the volume.",
            as: [("paragraph", "You trained 14 times, with chest carrying most of the volume.")]
        )
    }

    func testAnEmptyAnswerHasNoBlocks() {
        XCTAssertTrue(AnalysisTextFormatter.blocks(from: "").isEmpty)
        XCTAssertTrue(AnalysisTextFormatter.blocks(from: "\n\n  \n").isEmpty)
    }

    // MARK: - Inline emphasis

    func testInlineBoldIsResolvedAwayFromTheText() {
        let blocks = AnalysisTextFormatter.blocks(from: "Add **2.5 kg** on bench.")

        guard case .paragraph(let text) = blocks.first else {
            return XCTFail("expected a paragraph, got \(blocks)")
        }
        XCTAssertEqual(String(text.characters), "Add 2.5 kg on bench.")
        // Resolved, not dropped: the emphasis has to survive as an attribute.
        let bold = text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        XCTAssertTrue(bold, "the emphasis has to survive as an attribute")
    }

    func testInlineItalicIsResolvedAwayFromTheText() {
        assertRenders("Keep the reps *for now*.", as: [("paragraph", "Keep the reps for now.")])
    }

    /// Arithmetic in a recommendation is not emphasis, and must survive the
    /// pass unchanged.
    func testASpacedAsteriskIsLeftAlone() {
        assertRenders("Run 5 * 5 on squats.", as: [("paragraph", "Run 5 * 5 on squats.")])
    }

    // MARK: - Streaming

    /// The half-written marker at the end of a partial answer must show
    /// neither an asterisk nor a premature heading.
    func testAnUnclosedBoldMarkerIsNeitherShownNorTreatedAsAHeading() {
        assertRenders(
            "You trained 14 times.\n\n**Progressive Over",
            as: [("paragraph", "You trained 14 times."), ("paragraph", "Progressive Over")]
        )
    }

    func testAnUnclosedItalicMarkerIsNotShown() {
        assertRenders("Keep the reps *for", as: [("paragraph", "Keep the reps for")])
    }

    /// The same text one chunk later: now the pair is complete, and the line
    /// is the heading it was always going to be.
    func testTheClosedMarkerBecomesTheHeading() {
        assertRenders(
            "You trained 14 times.\n\n**Progressive Overload**",
            as: [("paragraph", "You trained 14 times."), ("heading", "Progressive Overload")]
        )
    }

    /// Whatever the stream is in the middle of, no asterisk reaches the screen.
    func testNoAsteriskSurvivesAnyPrefixOfAnAnswer() {
        let answer = """
        You trained 14 times.

        **Progressive Overload**
        - Add **2.5 kg** on bench
        - Keep the reps *for now*
        """
        for length in 1...answer.count {
            let partial = String(answer.prefix(length))
            let text = rendered(partial).map(\.text).joined(separator: "\n")
            XCTAssertFalse(text.contains("*"), "an asterisk showed at prefix length \(length)")
        }
    }

    // MARK: - plainText

    func testPlainTextDropsEveryMarker() {
        let plain = AnalysisTextFormatter.plainText(from: """
        **Progressive Overload**
        Add **2.5 kg** on bench.

        - Keep the reps *for now*
        """)

        XCTAssertEqual(plain, "Progressive Overload\nAdd 2.5 kg on bench.\nKeep the reps for now")
        XCTAssertFalse(plain.contains("*"))
    }

    func testPlainTextOfProseIsTheProse() {
        XCTAssertEqual(
            AnalysisTextFormatter.plainText(from: "You trained 14 times."),
            "You trained 14 times."
        )
    }

    func testPlainTextOfAnEmptyAnswerIsEmpty() {
        XCTAssertEqual(AnalysisTextFormatter.plainText(from: ""), "")
    }
}
