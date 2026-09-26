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

    /// The company behind the model, as the consent text and the privacy
    /// policy name it (US-4 AC4). The recipient of the data is the company,
    /// not the model — "Claude" is what answers, "Anthropic" is who receives.
    var vendorName: String {
        switch self {
        case .claude: return "Anthropic"
        case .gemini: return "Google"
        case .mistral: return "Mistral AI"
        }
    }

    /// `"Anthropic (Claude)"` — how the send-confirmation sheet and the
    /// history detail name a recipient (#268): the company that receives the
    /// data, and the model the user knows it by.
    var recipientName: String {
        "\(vendorName) (\(displayName))"
    }

    /// Where the provider processes the data, as the consent text states it
    /// (US-4 AC4): the USA for Anthropic and Google, the EU for Mistral AI.
    var processingRegion: String {
        switch self {
        case .claude, .gemini: return "USA"
        case .mistral: return "EU"
        }
    }

    /// The entity the user's own API contract is with, where it differs from
    /// the company that processes the data. Only Anthropic: a Swiss user
    /// contracts with Anthropic Ireland, Limited, while Anthropic PBC does the
    /// processing in the USA (US-4 AC4, ADR-005). `nil` where contract and
    /// processing sit with the same entity.
    var contractingEntity: String? {
        switch self {
        case .claude: return "Anthropic Ireland, Limited"
        case .gemini, .mistral: return nil
        }
    }

    /// The order the fallback chain tries providers in: the stored priority
    /// first, then every provider it does not name (#78, #268).
    ///
    /// Providers the order does not name are appended rather than dropped,
    /// exactly as the settings list repairs itself: a stored key outside the
    /// order is otherwise unreachable, and the analysis reports "no API key"
    /// while the user can see their key in Settings. That happens whenever
    /// the Keychain outlives `UserDefaults` — a reinstall keeps the keys but
    /// wipes the order — and on an install whose single key predates the
    /// multi-provider step (#78), which had no stored order at all.
    ///
    /// Shared by `InferenceService`, which walks it, and by the
    /// send-confirmation sheet, which shows it: the two must agree, or the
    /// user confirms a list that is not the one the run uses.
    static func fallbackOrder(from order: [LLMProvider]) -> [LLMProvider] {
        order + allCases.filter { !order.contains($0) }
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

    /// Where a plan restriction on this provider is lifted (#211). Only
    /// Mistral reports one: its Limits page shows the zero allowance and the
    /// current tier, and links on to Billing where pay-as-you-go is switched
    /// on. `nil` for providers that never answer with a plan restriction.
    var planURL: URL? {
        switch self {
        case .claude, .gemini: return nil
        case .mistral: return URL(staticString: "https://admin.mistral.ai/plateforme/limits")
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
