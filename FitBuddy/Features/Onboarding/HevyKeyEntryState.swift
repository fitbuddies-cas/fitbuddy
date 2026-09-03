import Foundation

/// UI state of the Hevy API-key entry screen (US-4, step 2).
enum HevyKeyEntryState: Equatable {
    /// Stored-key check (`bootstrap()`) has not finished yet — the root view
    /// shows a spinner instead of flashing the entry screen at returning users.
    case unknown
    /// Waiting for input; no validation attempt in flight.
    case idle
    /// Key is being verified against the Hevy API.
    case validating
    /// The last connect attempt failed.
    case failed(APIKeyEntryFailure)
    /// Key was validated and stored — onboarding can move to step 3.
    case connected
}
