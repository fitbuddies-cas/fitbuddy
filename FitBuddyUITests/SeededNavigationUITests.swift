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

    /// The second way into the statistics (#162): from a card inside a
    /// session, without going back to the dashboard and finding the movement
    /// in a list of dozens.
    @MainActor
    func testTappingAnExerciseInASessionOpensItsProgressionCurve() {
        let sut = SeededApp().launch()

        sut.assertAppears(sut.dashboard)
        sut.firstRow(of: sut.sessionRows).tap()
        sut.assertAppears(sut.workoutDetail)

        sut.firstRow(of: sut.exerciseCards).tap()

        sut.assertAppears(sut.progression)
        // The point of this route is the identity: a key built from the title
        // alone would miss every movement that carries a template id, and the
        // screen would answer "not in this window" for the exercise the user
        // is looking at. That failure has its own state, so assert it away.
        XCTAssertFalse(
            sut.unavailableNotice.exists,
            "The tapped exercise must resolve to the same movement the list would open"
        )
        // Whether a curve or the "not enough data" hint follows is the
        // movement's business, not this route's: the first card of a session
        // can be a cardio machine, which logs no weight and reps for Epley to
        // work from. What must hold is that the screen is about that movement.
        XCTAssertFalse(sut.app.navigationBars.element(boundBy: 0).identifier.isEmpty)
    }

    /// The history under the curve opens to the sets of that session (#163).
    @MainActor
    func testASessionInTheHistoryOpensItsSets() {
        let sut = SeededApp().launch()

        sut.assertAppears(sut.dashboard)
        sut.assertAppears(sut.exercisesLink)
        sut.exercisesLink.tap()
        sut.assertAppears(sut.exerciseList)
        sut.firstRow(of: sut.exerciseRows).tap()
        sut.assertAppears(sut.progression)

        sut.assertAppears(sut.history)
        // Collapsed to start with, or the assertion below would pass on a
        // screen that never reacted to the tap.
        XCTAssertEqual(sut.historySets.count, 0, "Sessions start collapsed")

        sut.expand(sut.firstRow(of: sut.historyRows))

        sut.assertAppears(sut.historySets.element(boundBy: 0))
    }

    /// Back out of the curve and the list is still the list — the forward path
    /// is only half of what a user does with a navigation stack.
    @MainActor
    func testBackFromTheCurveReturnsToTheList() {
        let sut = SeededApp().launch()

        sut.assertAppears(sut.dashboard)
        sut.assertAppears(sut.exercisesLink)
        sut.exercisesLink.tap()
        sut.assertAppears(sut.exerciseList)
        sut.firstRow(of: sut.exerciseRows).tap()
        sut.assertAppears(sut.progression)

        sut.backButton.tap()

        sut.assertAppears(sut.exerciseList)
    }
}
