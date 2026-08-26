import Foundation

/// UI state of the LLM API-key entry screen (US-4, step 3). Unlike the Hevy
/// key (step 2), the LLM keys are optional (AC2) and are not validated against
/// a live API before saving — they are only stored in the Keychain.
enum LLMKeysState: Equatable {
    /// Reasons a save attempt can fail.
    enum Failure: Equatable {
        /// A key could not be persisted to the Keychain.
        case keychain
    }

    /// Stored-key check (`bootstrap()`) has not finished yet — the root view
    /// shows a spinner instead of flashing the entry screen at returning users.
    case unknown
    /// Waiting for input; no save attempt in flight.
    case idle
    /// Keys are being written to the Keychain.
    case saving
    /// The last save attempt failed.
    case failed(Failure)
    /// At least one key was stored — onboarding can move to the dashboard.
    case saved
    /// The user chose to continue without any LLM key (AC2). AI analysis
    /// (US-3) stays unavailable until a key is added later.
    case skipped
}
