import Foundation

/// UI state of the Claude API-key entry screen (US-4, step 3). Unlike the Hevy
/// key (step 2), the Claude key is optional (AC2) and is not validated against
/// a live API before saving — it is only stored in the Keychain.
enum ClaudeKeyEntryState: Equatable {
    /// Reasons a save attempt can fail.
    enum Failure: Equatable {
        /// The key could not be persisted to the Keychain.
        case keychain
    }

    /// Stored-key check (`bootstrap()`) has not finished yet — the root view
    /// shows a spinner instead of flashing the entry screen at returning users.
    case unknown
    /// Waiting for input; no save attempt in flight.
    case idle
    /// Key is being written to the Keychain.
    case saving
    /// The last save attempt failed.
    case failed(Failure)
    /// Key was stored — onboarding can move to the dashboard.
    case saved
    /// The user chose to continue without a Claude key (AC2). AI analysis
    /// (US-3) stays unavailable until a key is added later.
    case skipped
}
