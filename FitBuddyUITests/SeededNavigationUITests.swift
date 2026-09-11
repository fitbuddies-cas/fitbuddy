import XCTest

/// End-to-end tests for the app's reading path over a seeded window (#148):
/// dashboard → session detail, and dashboard → exercise list → progression
/// curve.
///
/// What no unit test can see. Each of these screens has its own view-model
/// tests; what none of them cover is that the screens are *connected* — that a
/// row is tappable, that a `navigationDestination` hangs off the stack the push
/// happens on, and that the factories survive being threaded through three
/// views. A mistake there fails nothing and is invisible until someone taps.
final class SeededNavigationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        // A failed step leaves the app on a screen no later step understands.
        continueAfterFailure = false
    }

    /// The dashboard shows the seeded window, and a session row opens it.
    @MainActor
    func testTappingASessionOpensItsDetail() {
        let sut = SeededApp().launch()

        sut.assertAppears(sut.dashboard)
        let row = sut.firstRow(of: sut.sessionRows)
        row.tap()

        sut.assertAppears(sut.workoutDetail)
    }

    /// The path US-9 lives at the end of: the exercise list is reachable from
    /// the dashboard, and a movement opens its progression curve (#42).
    @MainActor
    func testTappingAnExerciseOpensItsProgressionCurve() {
        let sut = SeededApp().launch()

        sut.assertAppears(sut.dashboard)
        sut.assertAppears(sut.exercisesLink)
        sut.exercisesLink.tap()

        sut.assertAppears(sut.exerciseList)
        let row = sut.firstRow(of: sut.exerciseRows)
        row.tap()

        sut.assertAppears(sut.progression)
        // Person A trains every movement weekly for twelve weeks, so the first
        // row of the list has far more than the two sessions a curve needs —
        // the chart is what has to be there, not the "not enough data" notice.
        sut.assertAppears(sut.progressionChart)
        XCTAssertFalse(
            sut.insufficientDataNotice.exists,
            "A movement trained weekly for twelve weeks must have a plottable curve"
        )
    }

    /// Back out of the curve and the list is still the list — the forward path
    /// is only half of what a user does with a navigation stack.
    @MainActor
    func testBackFromTheCurveReturnsToTheList() {
        let sut = SeededApp().launch()

        sut.assertAppears(sut.dashboard)
        sut.exercisesLink.tap()
        sut.assertAppears(sut.exerciseList)
        sut.firstRow(of: sut.exerciseRows).tap()
        sut.assertAppears(sut.progression)

        sut.backButton.tap()

        sut.assertAppears(sut.exerciseList)
    }
}
