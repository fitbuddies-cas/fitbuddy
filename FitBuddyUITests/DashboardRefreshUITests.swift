import XCTest

/// Pull-to-refresh on a loaded dashboard (US-10 AC1).
///
/// Drives a real pull gesture against a dashboard that holds data, over a
/// stubbed sync slow enough to be interrupted, and asserts on what the user
/// sees afterwards: the seeded stub adds one session per sync, so a refresh
/// that ran to completion shows one more session than the launch did.
///
/// Written for a failure that left no other trace: SwiftUI cancels the
/// `.refreshable` task the moment the view re-renders, and the sync used to be
/// cancelled along with it — every pull died before its first request, the
/// timestamp never moved, and the only symptom was "nothing happens".
final class DashboardRefreshUITests: XCTestCase {
    @MainActor
    func testPullToRefreshRunsTheSyncToCompletion() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            LaunchArgument.resetState,
            LaunchArgument.stubHevy, LaunchArgument.Verdict.accepts,
            LaunchArgument.skipOnboarding,
            LaunchArgument.slowStubSync,
            LaunchArgument.seedMockWorkouts,
        ]
        app.launch()

        let dashboard = app.descendants(matching: .any)[AccessibilityID.Dashboard.root]
        XCTAssertTrue(dashboard.waitForExistence(timeout: OnboardingApp.timeout))

        // The launch sync takes three seconds under the slow stub and seeds the
        // mock window. Wait for its result, so the pull below refreshes a
        // loaded dashboard rather than racing the first sync.
        let seeded = app.staticTexts["60 total"]
        XCTAssertTrue(seeded.waitForExistence(timeout: 15), "the seeded dashboard should show the mock window")

        // A real pull: press near the top of the scroll view and drag down far
        // enough to trigger the refresh control. XCUITest holds the gesture
        // until the scroll view settles — with a working refresh that is when
        // the sync ends, so this call itself takes the stub's three seconds.
        let start = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)

        // One more session than the launch sync left: the pull's sync ran to
        // completion and the dashboard read the refreshed cache back. A
        // cancelled sync leaves "60 total" standing.
        let refreshed = app.staticTexts["61 total"]
        XCTAssertTrue(refreshed.waitForExistence(timeout: 10), "the pull should bring the refreshed window onto the dashboard")
    }
}
