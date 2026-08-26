import Foundation

/// UI state of the Hevy API-key entry screen (US-4, step 2).
enum HevyKeyEntryState: Equatable {
    /// Reasons the connect attempt can fail, each with its own banner copy.
    /// Shared with the settings key editor (#83), which runs the same
    /// enter-a-key interaction.
    enum Failure: Equatable {
        /// The provider rejected the key (HTTP 401).
        case invalidKey
        /// The provider could not be reached at all (offline, timeout, DNS…).
        case network
        /// The provider answered, but not with 200/401 (rate limit, outage…) —
        /// the key was not rejected and the connection works.
        case serviceUnavailable
        /// The key was accepted but could not be persisted to the Keychain.
        case keychain

        /// Banner headline.
        func title(for provider: String) -> String {
            switch self {
            case .invalidKey: return "\(provider) rejected this key (HTTP 401)"
            case .network: return "Could not reach \(provider)"
            case .serviceUnavailable: return "\(provider) is currently unavailable"
            case .keychain: return "Could not save your key"
            }
        }

        /// Banner body explaining what the user can do about it.
        func message(for provider: String) -> String {
            switch self {
            case .invalidKey:
                return "The key may be revoked or mistyped. Generate a new one in your \(provider) account, then paste it here."
            case .network:
                return "Check your internet connection and try again."
            case .serviceUnavailable:
                return "\(provider) answered with an unexpected error — your key was not rejected. Please try again in a little while."
            case .keychain:
                return "The key could not be stored on this device. Please try again."
            }
        }
    }

    /// Stored-key check (`bootstrap()`) has not finished yet — the root view
    /// shows a spinner instead of flashing the entry screen at returning users.
    case unknown
    /// Waiting for input; no validation attempt in flight.
    case idle
    /// Key is being verified against the Hevy API.
    case validating
    /// The last connect attempt failed.
    case failed(Failure)
    /// Key was validated and stored — onboarding can move to step 3.
    case connected
}
