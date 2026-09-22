import SwiftUI
import XCTest
@testable import FitBuddy

/// Rendering smoke tests for the result cards (#177).
///
/// Crash smoke tests, not layout tests: they catch a card that fails to
/// render — a bar width from a share, a metrics row whose cell count depends
/// on the RPE — but not one that renders wrongly. Views carry no unit tests in
/// this project; this is the narrow exception the dashboard and the
/// progression curve make too. The one size check below guards a specific
/// regression: a wrapping metric label.
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

    /// A mixed week fills four columns (#184), one more than design 3.5 drew.
    /// It still lays out, and no label wraps: the row is the height of the
    /// three-cell one.
    func testRecoveryCardRendersFourCellsForAMixedWeek() throws {
        guard case let .recovery(reasoning, metrics) = AnalysisReportSamples.recoveryCardMixedWeek else {
            return XCTFail("The sample must be a recovery card")
        }
        XCTAssertEqual(RecoveryMetricCell.cells(for: metrics).count, 4)

        try assertRenders(AnalysisReportCardView(card: AnalysisReportSamples.recoveryCardMixedWeek))

        let four = try render(
            RecoveryCardView(reasoning: reasoning, metrics: metrics).padding(.horizontal, 16)
        )
        let three = try render(
            RecoveryCardView(
                reasoning: reasoning,
                metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2)
            )
            .padding(.horizontal, 16)
        )

        XCTAssertEqual(four.size.height, three.size.height, accuracy: 0.5)
    }

    /// Truncation preserves height, so the height check above cannot see it
    /// (#184 review, finding 2). Every label of a row has to fit its column at
    /// the smallest scale `FBStat.compact` will apply — which "SUGGESTED REST"
    /// does not in a four-column row, hence the short "Rest" form there.
    ///
    /// The column widths are derived the way `RecoveryCardView` lays them out,
    /// at the 390 pt the other tests render at: 390 − 2×16 screen gutter −
    /// 2×16 `FBCard` − 2×12 row padding = 302 pt, less the gaps between cells.
    func testNoRecoveryLabelTruncatesInItsColumn() {
        let rows: [(metrics: RecoveryMetrics, spacing: CGFloat)] = [
            (RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2), 10),
            (RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil, averageHeartRate: 151), 10),
            (RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2, averageHeartRate: 148), 8),
        ]

        for row in rows {
            let cells = RecoveryMetricCell.cells(for: row.metrics)
            let count = CGFloat(cells.count)
            let column = (302 - row.spacing * (count - 1)) / count
            for cell in cells {
                let needed = Self.compactLabelWidth(cell.label) * FBStat.Size.compact.labelMinimumScaleFactor
                XCTAssertLessThanOrEqual(
                    needed,
                    column,
                    "\(cell.label) needs \(needed) pt in a \(column) pt column of a \(cells.count)-cell row"
                )
            }
        }
    }

    /// The width `FBStat.compact` needs for `label`: uppercased, caption2 at
    /// medium weight, with the tracking the size applies.
    private static func compactLabelWidth(_ label: String) -> CGFloat {
        let base = UIFont.preferredFont(forTextStyle: .caption2)
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium],
        ])
        let font = UIFont(descriptor: descriptor, size: base.pointSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: FBStat.Size.compact.labelTracking,
        ]
        return (label.uppercased() as NSString).size(withAttributes: attributes).width
    }

    /// Three cells or two, the metrics row keeps one line of labels: a
    /// wrapped "SUGGESTED REST" would push its value down and make the card
    /// taller than the one without the RPE cell.
    func testRecoveryCardHeightDoesNotDependOnTheRPECell() throws {
        let reasoning = "Take two rest days before the next heavy session."
        // Inset by the screen's 16 pt gutter, so the cells are as narrow as
        // on a standard iPhone.
        let withRPE = try render(
            RecoveryCardView(reasoning: reasoning, metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2))
                .padding(.horizontal, 16)
        )
        let withoutRPE = try render(
            RecoveryCardView(reasoning: reasoning, metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil))
                .padding(.horizontal, 16)
        )

        XCTAssertEqual(withRPE.size.height, withoutRPE.size.height, accuracy: 0.5)
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
        for report in [
            AnalysisReportSamples.progress,
            AnalysisReportSamples.recover,
            AnalysisReportSamples.hold,
            AnalysisReportSamples.thin,
        ] {
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

    /// Open and closed, the disclosure renders — and open is taller, so the
    /// summary is really laid out below the toggle.
    func testFullAnalysisRendersCollapsedAndExpanded() throws {
        let summary = AnalysisReportSamples.thin.summary
        let collapsed = try render(AnalysisFullAnalysisView(summary: summary, startsExpanded: false))
        let expanded = try render(AnalysisFullAnalysisView(summary: summary, startsExpanded: true))

        XCTAssertGreaterThan(collapsed.size.height, 0)
        XCTAssertGreaterThan(expanded.size.height, collapsed.size.height)
    }

    func testHistoryDetailRendersAStoredReportWithoutCards() throws {
        let report = AnalysisReportSamples.thin
        try assertRenders(
            AnalysisHistoryDetailView(
                entry: AnalysisResultSnapshot(
                    id: UUID(),
                    text: report.summary,
                    generatedAt: .now,
                    context: AnalysisContext(sessionCount: 2, window: .default),
                    report: report,
                    provider: .mistral
                ),
                now: .now
            ),
            height: 1_400
        )
    }

    /// A summary that only repeats the lead gets no disclosure, and the
    /// result still renders (#170 review).
    func testResultRendersAReportWhoseSummaryRepeatsItsLead() throws {
        let report = ValidatedAnalysisReport(
            headline: "Hold steady this week.",
            verdict: .hold,
            lead: "Keep your current loads.",
            cards: [],
            summary: "Keep your current loads."
        )
        XCTAssertFalse(report.hasFullAnalysis)

        try assertRenders(
            AnalysisResultView(
                outcome: .report(report),
                context: AnalysisContext(sessionCount: 2, window: .default),
                attribution: nil
            )
        )
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
                    text: AnalysisReportFactory.validatedEveryCard.summary,
                    generatedAt: .now,
                    context: AnalysisContext(sessionCount: 12, window: .default),
                    report: AnalysisReportFactory.validatedEveryCard,
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
        let image = try render(view, height: height, file: file, line: line)
        XCTAssertGreaterThan(image.size.height, 0, file: file, line: line)
    }

    /// Renders at the width of a standard iPhone.
    private func render(
        _ view: some View,
        height: CGFloat? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: 390, height: height))
        return try XCTUnwrap(renderer.uiImage, file: file, line: line)
    }
}
