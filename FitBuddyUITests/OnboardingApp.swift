import XCTest

/// Launches the app for an onboarding UI test and exposes the elements the
/// flow is driven through (#120).
///
/// A thin page object rather than raw queries in every test: the three tests
/// walk the same screens, and the one thing they must not disagree on is what
/// counts as "the confirm button". It also owns the launch arguments, which
/// are what make the flow testable at all — a stubbed key verdict and a forced
/// reset, both DEBUG-only seams in the app.
@MainActor
struct OnboardingApp {
    /// How long an element gets to appear. Generous on purpose, and measured:
    /// a cold simulator on the CI runner took ~25s from launch to the first
    /// screen. Only a failing run ever waits this long, so the budget costs
    /// nothing when things work — and a flaky timeout would cost more trust
    /// than the seconds it saves.
    static let timeout: TimeInterval = 30

    let app: XCUIApplication

    /// - Parameter keyVerdict: What the stubbed validator should answer in
    ///   step 2 — `accepts`, `rejects`, or `nil` to leave the live validator in
    ///   place (which no test does, since it would call Hevy).
    init(keyVerdict: String?) {
        app = XCUIApplication()
        // Every launch starts from a fresh install's state: the simulator keeps
        // the Keychain across app deletions and `UserDefaults` across
        // relaunches, so without this the second test of a run would already be
        // past onboarding.
        app.launchArguments = [LaunchArgument.resetState]
        if let keyVerdict {
            app.launchArguments += [LaunchArgument.stubHevy, keyVerdict]
        }
    }

    @discardableResult
    func launch() -> OnboardingApp {
        app.launch()
        return self
    }

    // MARK: - Elements

    var consentToggle: XCUIElement {
        app.switches[AccessibilityID.Consent.acceptToggle]
    }

    var consentConfirmButton: XCUIElement {
        app.buttons[AccessibilityID.Consent.confirmButton]
    }

    var keyField: XCUIElement {
        app.textFields[AccessibilityID.HevyKey.field]
    }

    var keyCTAButton: XCUIElement {
        app.buttons[AccessibilityID.HevyKey.ctaButton]
    }

    /// Queried across element types on purpose: SwiftUI decides what an
    /// accessibility container becomes, and the identifier is the part this
    /// test actually depends on.
    var keyErrorBanner: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.HevyKey.errorBanner]
    }

    var skipLLMKeysButton: XCUIElement {
        app.buttons[AccessibilityID.LLMKeys.skipButton]
    }

    /// Step 4 since US-13: the training profile, optional like step 3.
    var skipTrainingProfileButton: XCUIElement {
        app.buttons[AccessibilityID.TrainingProfile.skipButton]
    }

    var trainingProfileSaveButton: XCUIElement {
        app.buttons[AccessibilityID.TrainingProfile.saveButton]
    }

    func goalOption(_ goal: String) -> XCUIElement {
        app.buttons[AccessibilityID.TrainingProfile.goalOption(goal)]
    }

    var dashboard: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Dashboard.root]
    }

    // MARK: - Steps

    /// Ticks the consent checkbox and confirms — step 1 done.
    func grantConsent(file: StaticString = #filePath, line: UInt = #line) {
        assertAppears(consentToggle, file: file, line: line)
        switchOn(consentToggle, file: file, line: line)
        assertEnabled(consentConfirmButton, file: file, line: line)
        consentConfirmButton.tap()
    }

    /// Types `key` into step 2 and submits it with the keyboard's Go key.
    ///
    /// Submitting from the keyboard rather than by tapping the CTA on purpose:
    /// the button lives in a bottom safe-area inset, so with the software
    /// keyboard up a tap at its centre can land on a key instead — which is
    /// exactly what happened on CI, where no hardware keyboard is attached.
    /// The field's `.submitLabel(.go)` runs the same `connect()` the button
    /// does, and it is what a user with the keyboard open actually presses.
    func submitKey(_ key: String, file: StaticString = #filePath, line: UInt = #line) {
        assertAppears(keyField, file: file, line: line)
        keyField.tap()
        keyField.typeText(key + "\n")
    }

    // MARK: - Interactions

    /// Ticks a switch and makes sure it stayed ticked.
    ///
    /// A plain `tap()` is not enough right after a screen appears: the element
    /// query resolves a frame, and if the layout is still settling behind the
    /// launch — the consent screen arrives once the Keychain bootstrap
    /// resolves — the synthesized tap lands where the control no longer is.
    /// The failure then surfaces one step later as "the confirm button stayed
    /// disabled", which says nothing about the cause.
    private func switchOn(
        _ element: XCUIElement,
        attempts: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<attempts {
            guard element.value as? String != "1" else { return }
            element.tap()
            _ = element.waitForExistence(timeout: 1)
        }
        XCTAssertEqual(
            element.value as? String,
            "1",
            "\(element.identifier) did not switch on",
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

    /// Waits for an element that exists but may still be disabled — a button
    /// whose enabled state follows a `@Published` change one runloop later.
    func assertEnabled(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertAppears(element, file: file, line: line)
        let enabled = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabled, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: Self.timeout)
        XCTAssertEqual(
            result,
            .completed,
            "\(element.identifier) stayed disabled",
            file: file,
            line: line
        )
    }
}
