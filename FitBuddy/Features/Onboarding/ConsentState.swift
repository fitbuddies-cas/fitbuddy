import Foundation

/// Gates the app's root view based on whether the user has granted consent.
enum ConsentState: Equatable {
    /// Consent has not been checked yet (initial launch state).
    case unknown
    /// No valid consent stored — the consent screen must be shown.
    case required
    /// Consent for the current version is present — proceed into the app.
    case granted
}
