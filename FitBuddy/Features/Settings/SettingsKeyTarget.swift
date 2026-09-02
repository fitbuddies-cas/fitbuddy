import Foundation

/// Which stored credential a settings action (edit, delete) addresses.
///
/// `Identifiable` because it doubles as the `.sheet(item:)` selector for the
/// key editor, and `Hashable` so SwiftUI can diff it.
enum SettingsKeyTarget: Hashable, Identifiable {
    /// The Hevy API key (US-1) — the only mandatory credential.
    case hevy
    /// One LLM provider key (US-4).
    case llm(LLMProvider)

    var id: String {
        switch self {
        case .hevy: return "hevy"
        case .llm(let provider): return provider.rawValue
        }
    }

    /// Keychain slot backing this credential.
    var keychainKey: KeychainKey {
        switch self {
        case .hevy: return HevyKeyPresentation.keychainKey
        case .llm(let provider): return provider.keychainKey
        }
    }

    /// User-facing provider name.
    var displayName: String {
        switch self {
        case .hevy: return HevyKeyPresentation.displayName
        case .llm(let provider): return provider.displayName
        }
    }

    /// Text-field placeholder hinting at the key format.
    var keyPlaceholder: String {
        switch self {
        case .hevy: return HevyKeyPresentation.keyPlaceholder
        case .llm(let provider): return provider.keyPlaceholder
        }
    }

    /// Host name of the page that manages this key, for link labels.
    var consoleName: String {
        switch self {
        case .hevy: return HevyKeyPresentation.consoleName
        case .llm(let provider): return provider.consoleName
        }
    }

    /// Page where the user creates/manages this key.
    var consoleURL: URL {
        switch self {
        case .hevy: return HevyKeyPresentation.consoleURL
        case .llm(let provider): return provider.consoleURL
        }
    }

    /// Where-to-find instructions for this key (markdown).
    var consoleInstructions: String {
        switch self {
        case .hevy: return HevyKeyPresentation.consoleInstructions
        case .llm(let provider): return provider.consoleInstructions
        }
    }

    /// Whether the entered key is checked against the provider before it is
    /// stored. Only Hevy has a validation endpoint we use (US-1 AC1); the LLM
    /// keys are stored unverified and fail at the first analysis call (US-4).
    var isValidatedBeforeSaving: Bool {
        switch self {
        case .hevy: return true
        case .llm: return false
        }
    }
}
