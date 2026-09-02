import Foundation

/// Everything the key-entry screens need to talk about the Hevy API key:
/// its name, its Keychain slot, and where the user creates it. The LLM
/// equivalents live on `LLMProvider`, which has one instance per provider —
/// Hevy is the single fixed provider, so its counterpart is a namespace.
///
/// Named after the *presentation* of the key, not the key itself: the stored
/// secret is `KeychainKey.hevyAPIKey`.
enum HevyKeyPresentation {
    /// User-facing provider name.
    static let displayName = "Hevy"

    /// Text-field placeholder hinting at the Hevy key format.
    static let keyPlaceholder = "hv_live_…"

    /// Keychain slot holding the key.
    static let keychainKey = KeychainKey.hevyAPIKey

    /// Host name of the page that manages the key, for link labels.
    static let consoleName = "hevy.com"

    /// Hevy page where the user creates/manages API keys (US-4 AC3 error link).
    static let consoleURL = URL(staticString: "https://hevy.com/settings?developer")

    /// Where-to-find instructions shown on the key entry card (markdown).
    static let consoleInstructions = """
        The key is not available in the Hevy app — only on the Hevy website. \
        Log in at **hevy.com**, open **Settings → Developer**, and tap **Generate API key**.
        """
}
