import XCTest

/// Launches the app past onboarding with a mock training window already in the
/// cache, and exposes the screens the walk passes through (#148).
///
/// The counterpart to `OnboardingApp`: that one drives the flow a first-time
/// user sees, this one starts where that flow ends. Four launch arguments make
/// it deterministic — reset the stored state, skip onboarding, keep every Hevy
/// collaborator stubbed so nothing reaches the network, and seed the window.
@MainActor
struct SeededApp {
    /// Same budget as the onboarding suite: only a failing run waits it out,
    /// and a cold simulator on the CI runner is slow.
    static let timeout: TimeInterval = 30

    let app: XCUIApplication

    /// - Parameter profile: Which bundled history to seed — `person-a` trains
    ///   five times a week, `person-b` twice.
    init(profile: String = LaunchArgument.Profile.personA) {
        app = XCUIApplication()
        app.launchArguments = [
            // Honoured on this path too since #148: the forced reset runs
            // beside the seeding at launch, not out of the onboarding
            // bootstrap that `-fbSkipOnboarding` skips.
            LaunchArgument.resetState,
            LaunchArgument.skipOnboarding,
            // Without this the dashboard's own sync would run against Hevy with
            // no stored key, fail, and answer the screen with a banner instead
            // of the seeded window.
            LaunchArgument.stubHevy, LaunchArgument.Verdict.accepts,
            LaunchArgument.seedMockData, profile,
        ]
    }

    @discardableResult
    func launch() -> SeededApp {
        app.launch()
        return self
    }

    // MARK: - Elements

    var dashboard: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Dashboard.root]
    }

    /// Every session row shares one identifier — which of them opens is not
    /// what these tests are about.
    var sessionRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.Dashboard.sessionRow)
    }

    var workoutDetail: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.WorkoutDetail.root]
    }

    var exercisesLink: XCUIElement {
        app.buttons[AccessibilityID.Dashboard.exercisesLink]
    }

    var exerciseList: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Exercises.root]
    }

    var exerciseRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.Exercises.row)
    }

    var progression: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Progression.root]
    }

    var progressionChart: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Progression.chart]
    }

    var insufficientDataNotice: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Progression.insufficientData]
    }

    /// The system back button of the pushed screen.
    var backButton: XCUIElement {
        app.navigationBars.buttons.firstMatch
    }

    // MARK: - Assertions

    func assertAppears(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: Self.timeout),
            "\(element.identifier.isEmpty ? element.description : element.identifier) never appeared",
            file: file,
            line: line
        )
    }

    /// Waits until the query holds at least one element — the seeded window
    /// arrives through a cache read, so the rows are never there on the first
    /// frame.
    @discardableResult
    func firstRow(
        of rows: XCUIElementQuery,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let exists = NSPredicate(format: "count > 0")
        let expectation = XCTNSPredicateExpectation(predicate: exists, object: rows)
        let result = XCTWaiter().wait(for: [expectation], timeout: Self.timeout)
        XCTAssertEqual(result, .completed, "No rows appeared", file: file, line: line)
        return rows.element(boundBy: 0)
    }
}
