import Foundation

/// One stored LLM provider key as the settings screen shows it: the provider
/// plus a masked rendering. The plaintext is read once in
/// `SettingsViewModel.load()` and never kept — the screen has no reason to
/// hold a key it must not display.
struct LLMProviderKey: Identifiable, Equatable {
    let provider: LLMProvider
    /// Masked key, see `KeyMask`.
    let mask: String

    var id: LLMProvider { provider }
}
