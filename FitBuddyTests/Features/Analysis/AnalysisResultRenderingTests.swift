import SwiftUI
import XCTest
@testable import FitBuddy

/// Rendering smoke tests for the result cards (#177).
///
/// Views carry no unit tests in this project; this is the narrow exception the
/// dashboard and the progression curve make too. The cards lay out
/// data-dependent content — a bar width from a share, a metrics row whose cell
/// count depends on the RPE — and a layout that breaks on one of those fails at
/// render time, not in an assertion.
@MainActor
final class AnalysisResultRenderingTests: XCTestCase {
    // MARK: - Cards

    func testProgressionCardRenders() throws {
        try assertRenders(AnalysisReportCardView(card: AnalysisReportSamples.progressionCard))
    }

    func testRecoveryCardRendersWithAnRPE() throws {
        try assertRenders(AnalysisReportCardView(card: AnalysisReportSamples.recoveryCard))
    }

    /// The row the card lays out has no RPE cell, and still renders.
    func testRecoveryCardRendersWithoutAnRPE() throws {
        guard case let .recovery(_, metrics) = AnalysisReportSamples.recoveryCardWithoutRPE else {
            return XCTFail("The sample must be a recovery card")
        }
        XCTAssertFalse(RecoveryMetricCell.cells(for: metrics).contains { $0.label == "Avg RPE" })

        try assertRenders(AnalysisReportCardView(card: AnalysisReportSamples.recoveryCardWithoutRPE))
    }

    func testImbalanceCardRenders() throws {
        try assertRenders(AnalysisReportCardView(card: AnalysisReportSamples.imbalanceCard))
    }

    /// Neither group trained: both bars empty, no division by zero on screen.
    func testImbalanceCardRendersWithoutAnyFrequency() throws {
        try assertRenders(ImbalanceCardView(groupA: .chest, perWeekA: 0, groupB: .legs, perWeekB: 0, reasoning: "—"))
    }

    func testNoteCardRenders() throws {
        try assertRenders(AnalysisReportCardView(card: AnalysisReportSamples.noteCard))
    }

    func testHeadlineRendersForEveryVerdict() throws {
        for verdict in AnalysisVerdict.allCases {
            try assertRenders(AnalysisHeadlineView(verdict: verdict))
        }
    }

    // MARK: - Screens

    func testResultRendersEachReport() throws {
        for report in [AnalysisReportSamples.progress, AnalysisReportSamples.recover, AnalysisReportSamples.hold] {
            try assertRenders(
                AnalysisResultView(
                    outcome: .report(report),
                    context: AnalysisContext(sessionCount: 14, window: .default),
                    attribution: AnalysisAttribution(first: .claude),
                    age: "just now"
                )
            )
        }
    }

    func testResultRendersProse() throws {
        try assertRenders(
            AnalysisResultView(
                outcome: .prose("**Progressive overload**\n- Add 2.5 kg on bench"),
                context: AnalysisContext(sessionCount: 3, window: .default),
                attribution: nil
            )
        )
    }

    func testHistoryDetailRendersAStoredReport() throws {
        try assertRenders(
            AnalysisHistoryDetailView(
                entry: AnalysisResultSnapshot(
                    id: UUID(),
                    text: ValidatedAnalysisReportFixtures.everyCard.summary,
                    generatedAt: .now,
                    context: AnalysisContext(sessionCount: 12, window: .default),
                    report: ValidatedAnalysisReportFixtures.everyCard,
                    provider: .gemini
                ),
                now: .now
            ),
            height: 1_400
        )
    }

    // MARK: - Helpers

    /// - Parameter height: A fixed height for a view that scrolls, which has
    ///   no intrinsic height of its own to render at.
    private func assertRenders(
        _ view: some View,
        height: CGFloat? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let renderer = ImageRenderer(content: view.frame(width: 390, height: height))
        let image = try XCTUnwrap(renderer.uiImage, file: file, line: line)
        XCTAssertGreaterThan(image.size.height, 0, file: file, line: line)
    }
}
