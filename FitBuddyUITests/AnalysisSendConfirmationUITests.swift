import XCTest

/// End-to-end test for the confirmation sheet between "Analyze with AI" and
/// the transfer (US-3 AC12, #268).
///
/// What the view model tests cannot see: that the sheet actually stands in
/// front of the run on a device, that "Cancel" leaves the intro untouched,
/// and that "Send & analyze" only becomes tappable once the switch is on.
/// **Not run locally** — CI runs the UI suite (#120, #148).
final class AnalysisSendConfirmationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The button opens the sheet, not a run: the intro is still behind it,
    /// and the send button is disabled until the switch is on.
    @MainActor
    func testAnalyzeOpensTheSheetWithSendingDisabled() {
        let sut = SeededApp(profile: LaunchArgument.Profile.progressionReady).launch()

        openSheet(in: sut)

        XCTAssertFalse(sut.sendButton.isEnabled, "Sending must wait for the checkbox")
        sut.assertAppears(sut.sendConfirmationRecipients)
        sut.assertAppears(sut.sendConfirmationPrivacyLink)
    }

    /// Cancel sends nothing and puts the intro back exactly as it was.
    @MainActor
    func testCancelLeavesTheIntroUntouched() {
        let sut = SeededApp(profile: LaunchArgument.Profile.progressionReady).launch()

        openSheet(in: sut)
        sut.sendConfirmationCancelButton.tap()

        sut.assertDisappears(sut.sendConfirmationSheet)
        sut.assertAppears(sut.analysisStartButton)
        XCTAssertTrue(sut.analysisStartButton.isEnabled)
    }

    /// The ticked switch enables sending, and confirming leaves the intro:
    /// the run starts. With no provider key stored on this launch it ends on
    /// the missing-key screen — the transfer was still the user's call.
    @MainActor
    func testConfirmingStartsTheRun() {
        let sut = SeededApp(profile: LaunchArgument.Profile.progressionReady).launch()

        openSheet(in: sut)
        sut.switchOn(sut.sendConfirmationCheckbox)
        sut.assertEnabled(sut.sendButton)
        sut.sendButton.tap()

        sut.assertDisappears(sut.sendConfirmationSheet)
        sut.assertDisappears(sut.analysisStartButton)
    }

    // MARK: - Helpers

    /// Dashboard → analysis tab → "Analyze with AI" → the sheet.
    @MainActor
    private func openSheet(in sut: SeededApp) {
        sut.assertAppears(sut.dashboard)
        sut.select(sut.analysisTab)
        sut.assertAppears(sut.analysisStartButton)
        sut.analysisStartButton.tap()
        sut.assertAppears(sut.sendConfirmationSheet)
    }
}
