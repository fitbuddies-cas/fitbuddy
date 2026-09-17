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

    /// - Parameters:
    ///   - profile: Which bundled history to seed — `person-a` trains five
    ///     times a week, `person-b` twice, `progression-ready` and
    ///     `overreached` reproduce US-14 AC2 and AC4 (#179).
    ///   - analysisReport: Also stores an analysis with this report
    ///     (`LaunchArgument.Report`), so the analysis tab opens on its cards
    ///     (#177). `nil` stores none.
    init(profile: String = LaunchArgument.Profile.personA, analysisReport: String? = nil) {
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
        if let analysisReport {
            app.launchArguments += [LaunchArgument.seedAnalysis, analysisReport]
        }
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

    /// The exercise cards inside a session — each opens that movement's
    /// statistics (#162).
    var exerciseCards: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.WorkoutDetail.exerciseCard)
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

    var unavailableNotice: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Progression.unavailable]
    }

    var history: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Progression.history]
    }

    var historyRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.Progression.historyRow)
    }

    /// Set rows inside an opened session — none while every row is collapsed.
    var historySets: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.Progression.historySet)
    }

    var insufficientDataNotice: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Progression.insufficientData]
    }

    /// The analysis tab in the tab bar. Addressed by its title: a SwiftUI
    /// `Tab` exposes no identifier of its own.
    var analysisTab: XCUIElement {
        app.tabBars.buttons["Analysis"]
    }

    var analysisResult: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Analysis.result]
    }

    var analysisHeadline: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Analysis.headline]
    }

    var progressionCards: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.Analysis.progressionCard)
    }

    var recoveryCards: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.Analysis.recoveryCard)
    }

    var analysisLead: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Analysis.lead]
    }

    var fullAnalysisToggle: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Analysis.fullAnalysisToggle]
    }

    /// Present only while the "Show full analysis" disclosure is open.
    var fullAnalysis: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Analysis.fullAnalysis]
    }

    var analysisProse: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Analysis.prose]
    }

    /// The system back button of the pushed screen.
    var backButton: XCUIElement {
        app.navigationBars.buttons.firstMatch
    }

    // MARK: - Settings (#191)

    var settingsTab: XCUIElement {
        app.tabBars.buttons["Settings"]
    }

    /// The row that opens the training profile. Its label carries the
    /// summary under the title ("Training profile, Not set"), which is what
    /// the roundtrip test reads back.
    var trainingProfileRow: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.TrainingProfile.settingsRow]
    }

    /// One goal option on the profile screen, by `TrainingGoal.rawValue`.
    func goalOption(_ goal: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.TrainingProfile.goalOption(goal)]
    }

    /// Blocks until the element's label contains `text`.
    ///
    /// For state that arrives after the screen is already there — the row's
    /// summary is refreshed by an `onAppear` on the way back, so reading it
    /// right after the pop would read the old one.
    func assertLabel(
        of element: XCUIElement,
        contains text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: Self.timeout)
        XCTAssertEqual(result, .completed, "Label never contained \"\(text)\": \(element.label)", file: file, line: line)
    }

    /// Blocks until the progression screen has finished its read — the chart
    /// or the "not enough data" hint is on screen.
    ///
    /// `progression` alone is satisfied by the `.loading` state, so anything
    /// asserted about the *outcome* before this has waited would be asserted
    /// against a spinner.
    func awaitSettledProgression(file: StaticString = #filePath, line: UInt = #line) {
        let settled = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier IN %@",
                [AccessibilityID.Progression.chart, AccessibilityID.Progression.insufficientData]
            )
        )
        firstRow(of: settled, file: file, line: line)
    }

    // MARK: - Interactions

    /// Opens a collapsed session and makes sure it stayed open.
    ///
    /// A single tap is not enough right after the screen appears: the query
    /// resolves a frame, and if the layout is still settling — the chart above
    /// lays out as the cache read lands — the synthesized tap lands where the
    /// row no longer is. The test then fails 30 seconds later on the sets,
    /// which says nothing about the cause. Same lesson as the consent toggle
    /// in #120.
    func expand(
        _ row: XCUIElement,
        attempts: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<attempts {
            guard historySets.count == 0 else { return }
            row.tap()
            _ = historySets.element(boundBy: 0).waitForExistence(timeout: 2)
        }
        XCTAssertGreaterThan(
            historySets.count,
            0,
            "The session did not open",
            file: file,
            line: line
        )
    }

    /// Taps a selectable element — a tab bar button or a profile option — and
    /// makes sure the selection took.
    ///
    /// Same lesson as `expand(_:)`: a single tap can be swallowed while the
    /// screen is still settling. On a cold simulator the tab bar turns up
    /// before the first launch has settled, and the bar still has the
    /// dashboard selected (#179); right after a push the list is still laying
    /// out, and the option tap lands where the row no longer is (#197). Either
    /// way the test would fail 30 seconds later on the wrong screen with
    /// nothing pointing at the dropped tap. Waits for the element's own
    /// `isSelected` state, so a retry never undoes a selection that took.
    func select(
        _ element: XCUIElement,
        attempts: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertAppears(element, file: file, line: line)
        for _ in 0..<attempts {
            guard !element.isSelected else { return }
            element.tap()
            // A fresh expectation per attempt — one that was waited on and
            // not fulfilled cannot be waited on again.
            let selected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isSelected == true"),
                object: element
            )
            _ = XCTWaiter().wait(for: [selected], timeout: 3)
        }
        XCTAssertTrue(
            element.isSelected,
            "The tab or option never became selected",
            file: file,
            line: line
        )
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
