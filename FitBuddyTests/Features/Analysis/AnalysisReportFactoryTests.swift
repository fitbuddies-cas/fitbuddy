import XCTest
@testable import FitBuddy

/// Keeps `AnalysisReportFactory` honest (#179): every card kind has a fixture
/// in both forms, and each model answer survives the wire the way a
/// provider's would.
final class AnalysisReportFactoryTests: XCTestCase {
    func testEveryCardKindHasAModelAndAValidatedFixture() {
        for kind in AnalysisCard.Kind.allCases {
            XCTAssertEqual(AnalysisReportFactory.card(kind).kind, kind)
            XCTAssertEqual(AnalysisReportFactory.validatedCard(kind).kind, kind)
        }
        XCTAssertEqual(
            Set(AnalysisReportFactory.validatedEveryCard.cards.map(\.kind)),
            Set(AnalysisCard.Kind.allCases)
        )
    }

    /// Each verdict's answer, encoded as a provider sends it, decodes through
    /// the parser back into the same report — not into the prose fallback.
    func testEveryVerdictDecodesFromTheWire() throws {
        for verdict in AnalysisVerdict.modelChoices {
            let report = AnalysisReportFactory.report(verdict)
            XCTAssertEqual(report.verdict, verdict)
            let json = try XCTUnwrap(String(data: JSONEncoder().encode(report), encoding: .utf8))

            XCTAssertEqual(AnalysisReportParser.event(for: json), .report(report), "\(verdict)")
        }
    }

    func testTheProfileAnswersDecodeFromTheWire() throws {
        for report in [
            AnalysisReportFactory.progressionReady,
            AnalysisReportFactory.overreached,
            AnalysisReportFactory.thin,
        ] {
            let json = try XCTUnwrap(String(data: JSONEncoder().encode(report), encoding: .utf8))

            XCTAssertEqual(AnalysisReportParser.event(for: json), .report(report))
        }
    }

    /// #170: every model answer carries a lead, and the thin one no card.
    func testEveryAnswerHasALeadAndTheThinOneNoCards() {
        let answers = AnalysisVerdict.allCases.map(AnalysisReportFactory.report) + [
            AnalysisReportFactory.progressionReady,
            AnalysisReportFactory.overreached,
            AnalysisReportFactory.thin,
        ]
        for answer in answers {
            XCTAssertFalse(answer.lead.trimmingCharacters(in: .whitespaces).isEmpty, answer.headline)
        }
        XCTAssertTrue(AnalysisReportFactory.thin.cards.isEmpty)
        XCTAssertTrue(AnalysisReportSamples.thin.cards.isEmpty)
        XCTAssertFalse(AnalysisReportFactory.validatedEveryCard.lead.isEmpty)
    }
}
