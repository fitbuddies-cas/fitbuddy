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
        case .hevy: return .hevyAPIKey
        case .llm(let provider): return provider.keychainKey
        }
    }

    /// User-facing provider name.
    var displayName: String {
        switch self {
        case .hevy: return "Hevy"
        case .llm(let provider): return provider.displayName
        }
    }

    /// Text-field placeholder hinting at the key format.
    var keyPlaceholder: String {
        switch self {
        case .hevy: return HevyKeyEntryViewModel.keyPlaceholder
        case .llm(let provider): return provider.keyPlaceholder
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
