import Foundation

/// One announcement that a refresh the user asked for did not go through
/// (#43, US-10 AC2).
///
/// Exists next to `SyncStatus` rather than inside it because the two have
/// different lifetimes. `SyncStatus` is a standing description of the data —
/// it stays `.failed` for as long as the cache is stale, and the banner it
/// drives looks identical before and after a retry. This is the event: the
/// pull just now failed, said once and then gone.
struct RefreshNotice: Identifiable, Equatable {
    /// Fresh per announcement. Two failed pulls in a row usually produce the
    /// same `SyncFailure`, and without a changing identity the toast would
    /// never re-appear for the second one — which is precisely the case
    /// US-10 AC2 asks about.
    let id = UUID()
    let failure: SyncFailure
}
