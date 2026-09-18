import XCTest

/// End-to-end test for the structured result screen (US-14, #177).
///
/// What the card views' unit and rendering tests cannot see: that a report
/// stored by `AnalysisResultStore` survives the round trip through
/// persistence and the analysis tab's restore, and arrives as cards rather
/// than as the prose fallback.
final class AnalysisResultUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A seeded progress report opens on the verdict headline and at least one
    /// progression card — and not on the report's summary as prose.
    @MainActor
    func testASeededReportShowsAProgressionCard() {
        let sut = SeededApp(seedsAnalysis: true).launch()

        sut.assertAppears(sut.dashboard)
        sut.select(sut.analysisTab)

        sut.assertAppears(sut.analysisResult)
        sut.assertAppears(sut.analysisHeadline)
        sut.firstRow(of: sut.progressionCards)
        XCTAssertFalse(
            sut.analysisProse.exists,
            "A stored report must render as cards, not as its summary"
        )
    }
}
