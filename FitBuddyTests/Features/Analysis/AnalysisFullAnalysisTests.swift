import XCTest
@testable import FitBuddy

/// When "Show full analysis" starts open (US-14 AC1, #170).
final class AnalysisFullAnalysisTests: XCTestCase {
    func testStartsExpandedWithoutCards() {
        XCTAssertTrue(AnalysisFullAnalysis.startsExpanded(for: []))
    }

    /// A note is prose in a card, not something to act on.
    func testStartsExpandedWithNotesOnly() {
        XCTAssertTrue(AnalysisFullAnalysis.startsExpanded(for: [
            AnalysisReportSamples.noteCard,
            .note(title: "Sleep", text: "Keep sleep regular."),
        ]))
    }

    func testStartsCollapsedWithAProgressionCard() {
        XCTAssertFalse(AnalysisFullAnalysis.startsExpanded(for: [AnalysisReportSamples.progressionCard]))
    }

    func testStartsCollapsedWithARecoveryCard() {
        XCTAssertFalse(AnalysisFullAnalysis.startsExpanded(for: [AnalysisReportSamples.recoveryCard]))
    }

    func testStartsCollapsedWithAnImbalanceCard() {
        XCTAssertFalse(AnalysisFullAnalysis.startsExpanded(for: [AnalysisReportSamples.imbalanceCard]))
    }

    /// One actionable card among notes is enough to put the cards first.
    func testStartsCollapsedWithAnActionableCardAmongNotes() {
        XCTAssertFalse(AnalysisFullAnalysis.startsExpanded(for: [
            AnalysisReportSamples.noteCard,
            AnalysisReportSamples.imbalanceCard,
        ]))
    }

    func testEveryKindButTheNoteIsActionable() {
        XCTAssertEqual(AnalysisFullAnalysis.actionableKinds, Set(AnalysisCard.Kind.allCases).subtracting([.note]))
    }

    func testTheSamplesFollowTheRule() {
        XCTAssertFalse(AnalysisFullAnalysis.startsExpanded(for: AnalysisReportSamples.progress.cards))
        XCTAssertFalse(AnalysisFullAnalysis.startsExpanded(for: AnalysisReportSamples.recover.cards))
        XCTAssertTrue(AnalysisFullAnalysis.startsExpanded(for: AnalysisReportSamples.thin.cards))
    }

    func testToggleTitleAndValueFollowTheState() {
        XCTAssertEqual(AnalysisFullAnalysis.toggleTitle(isExpanded: false), "Show full analysis")
        XCTAssertEqual(AnalysisFullAnalysis.toggleTitle(isExpanded: true), "Hide full analysis")
        XCTAssertEqual(AnalysisFullAnalysis.accessibilityValue(isExpanded: false), "Collapsed")
        XCTAssertEqual(AnalysisFullAnalysis.accessibilityValue(isExpanded: true), "Expanded")
    }
}
