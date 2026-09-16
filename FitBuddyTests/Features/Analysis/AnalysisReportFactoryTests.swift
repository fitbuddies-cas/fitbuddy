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
        for verdict in AnalysisVerdict.allCases {
            let report = AnalysisReportFactory.report(verdict)
            XCTAssertEqual(report.verdict, verdict)
            let json = try XCTUnwrap(String(data: JSONEncoder().encode(report), encoding: .utf8))

            XCTAssertEqual(AnalysisReportParser.event(for: json), .report(report), "\(verdict)")
        }
    }

    func testTheProfileAnswersDecodeFromTheWire() throws {
        for report in [AnalysisReportFactory.progressionReady, AnalysisReportFactory.overreached] {
            let json = try XCTUnwrap(String(data: JSONEncoder().encode(report), encoding: .utf8))

            XCTAssertEqual(AnalysisReportParser.event(for: json), .report(report))
        }
    }
}
