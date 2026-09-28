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

    /// A stored progress report renders as the verdict headline, its lead and
    /// at least one progression card — not as its summary in prose. With an
    /// actionable card on screen, the full analysis starts collapsed (#170).
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
        sut.assertAppears(sut.analysisLead)
        sut.firstRow(of: sut.progressionCards)
        XCTAssertFalse(
            sut.analysisProse.exists,
            "A stored report must render as cards, not as its summary"
        )
        sut.assertAppears(sut.fullAnalysisToggle)
        XCTAssertFalse(sut.fullAnalysis.exists, "With cards on screen the full analysis starts collapsed")
    }

    /// Thin data (design 3.4b, #170): a stored report without cards shows its
    /// lead and the full analysis already open — no card and no prose
    /// fallback.
    @MainActor
    func testASeededThinReportShowsTheLeadAndTheOpenFullAnalysis() {
        let sut = SeededApp(
            profile: LaunchArgument.Profile.personB,
            analysisReport: LaunchArgument.Report.thin
        ).launch()

        openResult(in: sut)

        XCTAssertEqual(sut.analysisHeadline.label, "Hold steady this week.")
        sut.assertAppears(sut.analysisLead)
        sut.assertAppears(sut.fullAnalysisToggle)
        sut.assertAppears(sut.fullAnalysis)
        XCTAssertEqual(sut.progressionCards.count, 0)
        XCTAssertEqual(sut.recoveryCards.count, 0)
        XCTAssertFalse(sut.analysisProse.exists)
    }

    /// The fourth verdict class (#227, ADR-014 §6): the app's headline, the
    /// note naming why there is no verdict, and neither a progression nor a
    /// recovery card under it.
    @MainActor
    func testASeededReportWithoutAVerdictNamesWhyThereIsNone() {
        let sut = SeededApp(
            profile: LaunchArgument.Profile.personB,
            analysisReport: LaunchArgument.Report.insufficientData
        ).launch()

        openResult(in: sut)

        XCTAssertEqual(sut.analysisHeadline.label, "Not enough data to judge.")
        sut.assertAppears(sut.analysisLead)
        sut.assertAppears(sut.fullAnalysisToggle)
        sut.assertAppears(sut.fullAnalysis)
        XCTAssertEqual(sut.progressionCards.count, 0)
        XCTAssertEqual(sut.recoveryCards.count, 0)
        XCTAssertFalse(sut.analysisProse.exists)
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

    /// Design 3.4c (US-15 AC5, #186): an endurance report renders as metric
    /// cards and shows no progression card, i.e. no weight on the screen.
    ///
    /// Behind it the `runner` profile — 32 Strava runs through the real
    /// connector mapping (#188) — so the basis line the seeder builds is the
    /// one this cache justifies, and the screen is an endurance analysis from
    /// the cache up rather than a report dropped onto an unrelated history.
    /// **Not run locally** — CI runs the UI suite (#120, #148).
    @MainActor
    func testAnEnduranceReportOverTheRunnerProfileShowsMetricCards() {
        let sut = SeededApp(
            profile: LaunchArgument.Profile.runner,
            analysisReport: LaunchArgument.Report.endurance
        ).launch()

        openResult(in: sut)

        XCTAssertEqual(sut.analysisHeadline.label, "You're ready to progress.")
        sut.firstRow(of: sut.metricCards)
        XCTAssertEqual(sut.progressionCards.count, 0)
        XCTAssertFalse(sut.analysisProse.exists)
        // One endurance source, named as such, and the profile it was run
        // under (US-15 AC1/AC4).
        sut.assertLabel(of: sut.analysisContext, contains: "Strava sessions")
        sut.assertLabel(of: sut.analysisContext, contains: "Endurance")
    }

    /// Design 3.4d over the `mixed` profile: the interference card leads, a
    /// metric card sits under it, and the basis line names both sources
    /// (US-15 AC4, #188).
    ///
    /// The cache-to-card path the #186 version could not walk: the counts come
    /// out of the seeded window through `AnalysisContext.counts`, not
    /// out of a fixture.
    @MainActor
    func testAnOverallLoadReportOverTheMixedProfileNamesBothSources() {
        let sut = SeededApp(
            profile: LaunchArgument.Profile.mixed,
            analysisReport: LaunchArgument.Report.overallLoad
        ).launch()

        openResult(in: sut)

        XCTAssertEqual(sut.analysisHeadline.label, "Hold steady this week.")
        sut.firstRow(of: sut.interferenceCards)
        sut.firstRow(of: sut.metricCards)
        XCTAssertFalse(sut.analysisProse.exists)
        sut.assertLabel(of: sut.analysisContext, contains: "Hevy")
        sut.assertLabel(of: sut.analysisContext, contains: "Strava")
        sut.assertLabel(of: sut.analysisContext, contains: "Overall load")
    }

    // MARK: - Helpers

    /// Dashboard → analysis tab → the restored result and its headline.
    @MainActor
    private func openResult(in sut: SeededApp) {
        sut.assertAppears(sut.dashboard)
        sut.select(sut.analysisTab)

        sut.assertAppears(sut.analysisResult)
        sut.assertAppears(sut.analysisHeadline)
    }
}
