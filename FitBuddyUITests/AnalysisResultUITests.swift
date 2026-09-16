import XCTest

/// End-to-end test for the structured result screen (US-14, #177, #179).
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

    /// A stored progress report renders as the verdict headline and at least
    /// one progression card — not as its summary in prose.
    ///
    /// The report goes straight into the store, so the profile does not
    /// produce it; it is seeded only to put a matching history behind the
    /// screen. The profile's own path to the card is covered end-to-end in
    /// `AnalysisMockProfileTests`.
    @MainActor
    func testASeededReportShowsAProgressionCard() {
        let sut = SeededApp(
            profile: LaunchArgument.Profile.progressionReady,
            analysisReport: LaunchArgument.Report.progress
        ).launch()

        openResult(in: sut)

        XCTAssertEqual(sut.analysisHeadline.label, "You're ready to progress.")
        sut.firstRow(of: sut.progressionCards)
        XCTAssertFalse(
            sut.analysisProse.exists,
            "A stored report must render as cards, not as its summary"
        )
    }

    /// A stored recovery report renders as its own headline and the recovery
    /// card, with no progression card and no prose.
    ///
    /// Rendering only: the report is stored directly, and the `overreached`
    /// profile just puts a matching history behind the screen. US-14 AC4 —
    /// six of seven days forcing the recovery card — is covered end-to-end in
    /// `AnalysisMockProfileTests`.
    @MainActor
    func testASeededRecoveryReportShowsTheRecoveryCard() {
        let sut = SeededApp(
            profile: LaunchArgument.Profile.overreached,
            analysisReport: LaunchArgument.Report.recover
        ).launch()

        openResult(in: sut)

        XCTAssertEqual(sut.analysisHeadline.label, "Recover this week.")
        sut.firstRow(of: sut.recoveryCards)
        XCTAssertEqual(sut.progressionCards.count, 0)
        XCTAssertFalse(sut.analysisProse.exists)
    }

    // MARK: - Helpers

    /// Dashboard → analysis tab → the restored result and its headline.
    @MainActor
    private func openResult(in sut: SeededApp) {
        sut.assertAppears(sut.dashboard)
        sut.assertAppears(sut.analysisTab)
        sut.analysisTab.tap()

        sut.assertAppears(sut.analysisResult)
        sut.assertAppears(sut.analysisHeadline)
    }
}
