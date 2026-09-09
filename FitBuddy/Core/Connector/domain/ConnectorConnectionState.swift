import Foundation

/// How usable a registered connector's credentials currently are, as reported
/// by `ConnectorRegistry.state(of:now:)`.
///
/// Expiry is a state of its own rather than a flag on `connected`, because the
/// three cases lead to three different screens: nothing to show, sync as
/// usual, or the "renew your connection" prompt from US-5 AC2.
enum ConnectorConnectionState: Equatable, Sendable {
    /// No credentials were ever accepted for this source, or they were
    /// dropped again by `disconnect`.
    case disconnected
    /// Credentials are in place. `expiresAt` is `nil` for schemes that do not
    /// expire (Hevy's API key) and a future date for an OAuth token.
    case connected(expiresAt: Date?)
    /// The OAuth token's `expiresAt` has passed. The connector keeps the
    /// credentials — only the user can renew them.
    case expired(since: Date)

    /// Whether the user has to act before this source can sync again.
    var needsRenewal: Bool {
        if case .expired = self { return true }
        return false
    }
}
