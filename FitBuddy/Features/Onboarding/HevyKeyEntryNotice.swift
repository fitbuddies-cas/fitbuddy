import Foundation

/// Why the app put the user back on the Hevy key screen without them asking
/// for it (US-8 AC2).
///
/// The route back to step 2 is the same for a revoked key and for a key the
/// user deleted themselves in Settings, but only one of the two needs
/// explaining. Without this the revoked case is a screen the user never asked
/// for and gets no reason for — which is the "silent" failure US-8 AC2 rules
/// out just as much as carrying on with cached data would be.
enum HevyKeyEntryNotice: Equatable {
    /// A sync came back HTTP 401: the stored key was revoked or regenerated in
    /// the Hevy account, so `WorkoutSyncService` dropped it.
    case keyRejected

    var title: String {
        switch self {
        case .keyRejected:
            return "\(HevyKeyPresentation.displayName) rejected your saved key"
        }
    }

    var message: String {
        switch self {
        case .keyRejected:
            return """
            The key stored on this device no longer works — it was most likely revoked or \
            regenerated in your \(HevyKeyPresentation.displayName) account. FitBuddy stopped \
            syncing and removed it. Paste a new key to pick your training data back up.
            """
        }
    }

    var symbolName: String {
        switch self {
        case .keyRejected:
            return "key.slash"
        }
    }
}
