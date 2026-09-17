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
    /// AI Studio issues `AQ.…` keys since 2026; older ones start with `AIza`
    /// and still work (#209).
    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-…"
        case .gemini: return "AQ.…"
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

    /// A warning about how this provider treats the data sent to it, shown
    /// under its key field. `nil` where there is nothing the user has to act
    /// on (ADR-007).
    ///
    /// Only Mistral has one today: its free Experiment tier trains on API
    /// input by default, which for training data means health data. FitBuddy
    /// cannot switch that off from here — only tell the user where to.
    var dataUsageNote: String? {
        switch self {
        case .claude, .gemini:
            return nil
        case .mistral:
            return "Mistral's free Experiment tier uses API data for training by default. "
                + "Enable pay-as-you-go, or turn training off under Privacy in the Mistral admin console, "
                + "before you send workout data."
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
