import XCTest

/// End-to-end tests for the onboarding flow (US-4, #120): consent → Hevy key →
/// LLM keys → dashboard.
///
/// The suite the unit tests cannot replace. Every step of this flow is covered
/// by view-model tests already — what none of them prove is that the screens
/// are wired to those view models, that the navigation advances, and that a
/// user who taps through in order actually reaches the dashboard. That is also
/// exactly what breaks unnoticed, and it is the first thing a tester sees.
///
/// No test here touches the network or a real key: the Hevy verdict is stubbed
/// through a launch argument (`StubHevyKeyValidator`), and each launch resets
/// the stored state first.
final class OnboardingFlowUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        // A failed step leaves the app on a screen no later step understands,
        // so the remaining assertions would report the same break again.
        continueAfterFailure = false
    }

    /// The whole flow, in the order a first-time tester walks it.
    @MainActor
    func testCompletingOnboardingReachesTheDashboard() {
        let sut = OnboardingApp(keyVerdict: "accepts").launch()

        sut.grantConsent()
        sut.submitKey("hv_live_uitest")
        sut.assertAppears(sut.skipLLMKeysButton)
        sut.skipLLMKeysButton.tap()

        sut.assertAppears(sut.dashboard)
    }

    /// A key Hevy rejects: the flow has to say so and stay where it is — the
    /// user's next move is pasting a different key, not being pushed onwards.
    @MainActor
    func testRejectedKeyShowsTheErrorAndKeepsTheUserOnStepTwo() {
        let sut = OnboardingApp(keyVerdict: "rejects").launch()

        sut.grantConsent()
        sut.submitKey("hv_live_revoked")

        sut.assertAppears(sut.keyErrorBanner)
        XCTAssertFalse(
            sut.skipLLMKeysButton.exists,
            "A rejected key must not advance the flow to step 3"
        )

        // The CTA turns into the way back into editing (`retry()`), so the
        // screen offers a next move rather than a dead end.
        sut.assertEnabled(sut.keyCTAButton)
        XCTAssertEqual(sut.keyCTAButton.label, "Try again")
        sut.keyCTAButton.tap()
        XCTAssertFalse(
            sut.keyErrorBanner.exists,
            "Tapping the retry CTA must clear the failure and return to input"
        )
        sut.assertAppears(sut.keyField)
    }

    /// Consent is a gate, not a formality (US-4 AC4): without the checkbox
    /// there is no way past step 1.
    @MainActor
    func testWithoutConsentTheFlowDoesNotAdvance() {
        let sut = OnboardingApp(keyVerdict: "accepts").launch()

        sut.assertAppears(sut.consentConfirmButton)
        XCTAssertFalse(
            sut.consentConfirmButton.isEnabled,
            "The confirm button must stay disabled until the checkbox is ticked"
        )

        sut.consentConfirmButton.tap()

        XCTAssertFalse(sut.keyField.exists, "Step 2 must not be reachable without consent")
        sut.assertAppears(sut.consentToggle)
    }
}
