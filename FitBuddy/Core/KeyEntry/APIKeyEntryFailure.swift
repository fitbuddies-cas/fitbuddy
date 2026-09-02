import Foundation

/// Reasons an API-key entry attempt can fail, each with its own banner copy.
///
/// Shared by every "enter an API key" screen: onboarding step 2
/// (`HevyKeyEntryState`), onboarding step 3 (`LLMKeysState`) and the settings
/// key editor (`KeyEditorState`, #83). The copy is parameterized on the
/// provider name so the same case can be shown for Hevy as well as for an LLM
/// provider.
enum APIKeyEntryFailure: Equatable {
    /// The provider rejected the key (HTTP 401).
    case invalidKey
    /// The provider could not be reached at all (offline, timeout, DNS…).
    case network
    /// The provider answered, but not with 200/401 (rate limit, outage…) —
    /// the key was not rejected and the connection works.
    case serviceUnavailable
    /// The key was accepted but could not be persisted to the Keychain.
    case keychain

    /// Maps a validator error onto the failure the user is shown. Exhaustive
    /// on purpose and deliberately the only such mapping in the app: a new
    /// validator case (say `.rateLimited`) must make one conscious copy
    /// decision here instead of silently inheriting the "check your internet"
    /// advice — or, worse, being decided twice and differently per screen.
    init(_ error: HevyKeyValidationError) {
        switch error {
        case .invalidKey: self = .invalidKey
        case .transport: self = .network
        case .unexpectedStatus: self = .serviceUnavailable
        }
    }

    /// Banner headline.
    ///
    /// - Parameter provider: Name of the provider the attempt was made
    ///   against, or `nil` where no single one is in play — onboarding step 3
    ///   saves up to three provider keys in one go, so only `.keychain` can
    ///   reach it, and that case names nobody anyway.
    func title(for provider: String? = nil) -> String {
        switch self {
        case .invalidKey: return "\(Self.name(provider)) rejected this key (HTTP 401)"
        case .network: return "Could not reach \(Self.inlineName(provider))"
        case .serviceUnavailable: return "\(Self.name(provider)) is currently unavailable"
        case .keychain: return "Could not save your key"
        }
    }

    /// Banner body explaining what the user can do about it.
    func message(for provider: String? = nil) -> String {
        switch self {
        case .invalidKey:
            return "The key may be revoked or mistyped. Generate a new one in your \(Self.inlineName(provider)) account, then paste it here."
        case .network:
            return "Check your internet connection and try again."
        case .serviceUnavailable:
            return "\(Self.name(provider)) answered with an unexpected error — your key was not rejected. Please try again in a little while."
        case .keychain:
            return "The key could not be stored on this device. Please try again."
        }
    }

    /// Provider name at the start of a sentence.
    private static func name(_ provider: String?) -> String {
        provider ?? "The provider"
    }

    /// Provider name inside a sentence.
    private static func inlineName(_ provider: String?) -> String {
        provider ?? "the provider"
    }
}
