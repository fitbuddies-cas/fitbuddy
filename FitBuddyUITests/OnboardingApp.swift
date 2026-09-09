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
    /// How long an element gets to appear. Generous on purpose: the runner is
    /// shared and a cold app launch on a busy machine is slow, and a flaky
    /// timeout would cost more trust than the seconds it saves.
    static let timeout: TimeInterval = 20

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
        app.launchArguments = ["-fbResetState"]
        if let keyVerdict {
            app.launchArguments += ["-fbStubHevy", keyVerdict]
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

    var dashboard: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.Dashboard.root]
    }

    // MARK: - Steps

    /// Ticks the consent checkbox and confirms — step 1 done.
    func grantConsent(file: StaticString = #filePath, line: UInt = #line) {
        assertAppears(consentToggle, file: file, line: line)
        consentToggle.tap()
        assertEnabled(consentConfirmButton, file: file, line: line)
        consentConfirmButton.tap()
    }

    /// Types `key` into step 2 and submits it.
    func submitKey(_ key: String, file: StaticString = #filePath, line: UInt = #line) {
        assertAppears(keyField, file: file, line: line)
        keyField.tap()
        keyField.typeText(key)
        assertEnabled(keyCTAButton, file: file, line: line)
        keyCTAButton.tap()
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
