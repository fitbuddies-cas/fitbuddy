import Foundation

/// Presentation details of the Hevy API key that both onboarding step 2 and
/// the settings key editor (#83) need. The LLM equivalents live on
/// `LLMProvider`, which has one instance per provider.
enum HevyAPIKey {
    /// Text-field placeholder hinting at the Hevy key format.
    static let keyPlaceholder = "hv_live_…"
}
