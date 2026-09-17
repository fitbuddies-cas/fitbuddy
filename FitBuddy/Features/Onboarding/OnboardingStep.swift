import Foundation

/// Current position in the 4-step onboarding flow (US-4, US-13), derived and
/// advanced by `OnboardingViewModel`. `Hashable` because the key steps double as
/// `NavigationStack` path elements in `OnboardingFlowView`.
enum OnboardingStep: Hashable {
    /// Child bootstraps are still resolving persisted state — the root view
    /// shows a spinner instead of flashing the wrong step at returning users.
    case loading
    /// Step 1: consent to data processing.
    case consent
    /// Step 2: Hevy API key entry + validation.
    case hevyKey
    /// Step 3: optional LLM provider key entry (or skip).
    case llmKeys
    /// Step 4: optional training goal and experience (or skip), US-13.
    case trainingProfile
    /// Onboarding finished — the app surface (dashboard, #27) takes over.
    case completed
}
