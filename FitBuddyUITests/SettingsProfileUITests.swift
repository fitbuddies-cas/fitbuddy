import XCTest

/// End-to-end test for the training profile in Settings (US-13 AC5, #191):
/// the row opens the profile, a change on that screen is what the row shows
/// once the user is back.
///
/// The second half is the point. The row is refreshed by an `onAppear` on
/// the way back, and whether that modifier sits on the list or on the stack
/// around it decides whether it fires at all on a pop — a mistake no unit
/// test can see, because the view model is right either way.
final class SettingsProfileUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        // A failed step leaves the app on a screen no later step understands.
        continueAfterFailure = false
    }

    @MainActor
    func testChangingTheGoalInSettingsShowsOnTheRowAfterGoingBack() {
        let sut = SeededApp().launch()

        sut.assertAppears(sut.dashboard)
        sut.settingsTab.tap()
        sut.assertAppears(sut.trainingProfileRow)
        // `-fbSkipOnboarding` walks past step 4 without answering it.
        sut.assertLabel(of: sut.trainingProfileRow, contains: "Not set")
        sut.trainingProfileRow.tap()

        sut.select(sut.goalOption("improve_endurance"))
        sut.backButton.tap()

        sut.assertAppears(sut.trainingProfileRow)
        sut.assertLabel(of: sut.trainingProfileRow, contains: "Improve endurance")
    }
}
