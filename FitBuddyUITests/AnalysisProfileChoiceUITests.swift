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
/// **Not run locally** — CI runs the UI suite (#120, #148).
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
        let segments = sut.analysisProfilePicker.buttons
        XCTAssertEqual(segments.count, 3)
        XCTAssertTrue(segments["Overall load"].isSelected, "Overall load is the default for two domains")
        XCTAssertTrue(segments["Strength"].exists)
        XCTAssertTrue(segments["Endurance"].exists)
    }

    /// The picker moves when it is tapped, so the run that follows is the one
    /// the user asked for.
    @MainActor
    func testAProfileCanBePicked() {
        let sut = SeededApp(profile: LaunchArgument.Profile.mixed).launch()

        openIntro(in: sut)
        sut.assertAppears(sut.analysisProfilePicker)
        sut.select(sut.analysisProfilePicker.buttons["Endurance"])

        XCTAssertTrue(sut.analysisProfilePicker.buttons["Endurance"].isSelected)
    }

    /// One kind of training in the window is not a choice: a segmented control
    /// with a single segment is a label, so the runner gets none and the run
    /// is implicitly an endurance analysis (US-15 AC1).
    @MainActor
    func testTheRunnerProfileOffersNoChoice() {
        let sut = SeededApp(profile: LaunchArgument.Profile.runner).launch()

        openIntro(in: sut)

        XCTAssertFalse(sut.analysisProfilePicker.exists, "An endurance-only window has nothing to choose")
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
