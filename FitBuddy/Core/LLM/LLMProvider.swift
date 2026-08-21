import Foundation

/// LLM providers the user can bring their own API key for (US-4, step 3).
/// The order in which the user adds keys during onboarding is the fallback
/// priority for analysis calls, persisted via `LLMPriorityStore`.
enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case gemini
    case mistral

    var id: String { rawValue }

    /// User-facing name shown in the provider picker.
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .mistral: return "Mistral"
        }
    }

    /// Text-field placeholder hinting at the provider's key format. Mistral
    /// keys have no recognizable prefix, so a generic hint is shown instead.
    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-…"
        case .gemini: return "AIza…"
        case .mistral: return "Your Mistral API key"
        }
    }

    /// Host name of the provider's console, for link labels.
    var consoleName: String {
        switch self {
        case .claude: return "console.anthropic.com"
        case .gemini: return "aistudio.google.com"
        case .mistral: return "console.mistral.ai"
        }
    }

    /// Console page where the user creates/manages API keys.
    var consoleURL: URL {
        switch self {
        case .claude: return URL(staticString: "https://console.anthropic.com/settings/keys")
        case .gemini: return URL(staticString: "https://aistudio.google.com/apikey")
        case .mistral: return URL(staticString: "https://console.mistral.ai/api-keys")
        }
    }

    /// Where-to-find instructions shown on the key entry card (markdown).
    var consoleInstructions: String {
        switch self {
        case .claude:
            return "Log in at **console.anthropic.com**, open **Settings → API Keys**, and tap **Create Key**."
        case .gemini:
            return "Log in at **aistudio.google.com**, open **Get API key**, and tap **Create API key**."
        case .mistral:
            return "Log in at **console.mistral.ai**, open **API Keys**, and tap **Create new key**."
        }
    }

    /// Keychain slot holding this provider's key.
    var keychainKey: KeychainKey {
        switch self {
        case .claude: return .claudeAPIKey
        case .gemini: return .geminiAPIKey
        case .mistral: return .mistralAPIKey
        }
    }
}
