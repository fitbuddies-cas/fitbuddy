import XCTest

/// The profile picker of US-15 AC1 on the intro screen, over the cross-source
/// mock profiles (#185, #188).
///
/// What the view model's unit tests cannot see: that the picker the user
/// actually meets is built from the seeded cache — three segments over a week
/// of lifting and running, none at all over a window with one kind of training
/// in it. The cache is filled through the real connector mapping, so this is
/// the same path a synced install takes.
///
/// No analysis is seeded here on purpose: with a stored report the tab
/// restores straight to the result and the intro is never shown.
///
/// **Not run locally** — CI runs the UI suite (#120, #148). The segmented
/// control is addressed by element type (see `SeededApp.analysisProfilePicker`);
/// the first CI run is what confirms that query.
final class AnalysisProfileChoiceUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A window of lifts and endurance sessions offers all three profiles,
    /// "Overall load" preselected (US-15 AC1).
    @MainActor
    func testTheMixedProfileOffersThreeAnalysisProfiles() {
        let sut = SeededApp(profile: LaunchArgument.Profile.mixed).launch()

        openIntro(in: sut)

        sut.assertAppears(sut.analysisProfilePicker)
        XCTAssertEqual(sut.analysisProfilePicker.buttons.count, 3)
        XCTAssertTrue(sut.analysisProfileSegment("Strength").exists)
        XCTAssertTrue(sut.analysisProfileSegment("Endurance").exists)
        XCTAssertTrue(
            sut.analysisProfileSegment("Overall load").isSelected,
            "Overall load is the default where the window holds both domains"
        )
    }

    /// Picking a segment moves the selection off the preselected one, so the
    /// run that follows is about what the user asked for rather than about the
    /// default.
    @MainActor
    func testPickingAProfileReleasesThePreselectedOne() {
        let sut = SeededApp(profile: LaunchArgument.Profile.mixed).launch()

        openIntro(in: sut)
        sut.assertAppears(sut.analysisProfilePicker)
        // `select` retries the tap and asserts that the new segment took. What
        // it cannot say is that the old one let go — the half that makes this
        // one selection rather than two.
        sut.select(sut.analysisProfileSegment("Endurance"))

        XCTAssertFalse(sut.analysisProfileSegment("Overall load").isSelected)
    }

    /// One kind of training in the window is not a choice: a segmented control
    /// with a single segment is a label, so the runner gets none and the run is
    /// implicitly an endurance analysis (US-15 AC1).
    ///
    /// Waited out rather than asserted on the spot. The intro renders before
    /// `prepareProfileSelection()` has read the cache, so a bare `exists` is
    /// false at that moment whatever the window holds — the test would pass
    /// over a cache that *does* offer a choice and prove nothing (#188 review).
    /// The wait costs its full budget on a green run; that is what an assertion
    /// which can actually fail costs here.
    @MainActor
    func testTheRunnerProfileOffersNoChoice() {
        let sut = SeededApp(profile: LaunchArgument.Profile.runner).launch()

        openIntro(in: sut)

        XCTAssertFalse(
            sut.analysisProfilePicker.waitForExistence(timeout: SeededApp.timeout),
            "An endurance-only window has nothing to choose"
        )
    }

    // MARK: - Helpers

    /// Dashboard → analysis tab → the intro screen with its start button.
    @MainActor
    private func openIntro(in sut: SeededApp) {
        sut.assertAppears(sut.dashboard)
        sut.select(sut.analysisTab)
        sut.assertAppears(sut.app.buttons["Analyze with AI"])
    }
}
