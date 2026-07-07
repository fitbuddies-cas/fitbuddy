import Foundation

/// UI state of the Hevy API-key entry screen (US-4, step 1).
enum HevyKeyEntryState: Equatable {
    /// Reasons the connect attempt can fail, each with its own banner copy.
    enum Failure: Equatable {
        /// Hevy rejected the key (HTTP 401).
        case invalidKey
        /// Hevy could not be reached at all (offline, timeout, DNS…).
        case network
        /// Hevy answered, but not with 200/401 (rate limit, outage…) — the
        /// key was not rejected and the connection works.
        case serviceUnavailable
        /// The key validated but could not be persisted to the Keychain.
        case keychain
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
    /// Key was validated and stored — onboarding can move to step 2.
    case connected
}
