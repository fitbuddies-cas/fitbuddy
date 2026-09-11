import Foundation

/// One data source as the dashboard's status strip reports it: which provider,
/// when it last delivered, and whether it is delivering right now (US-8).
///
/// Keyed by `ConnectorSource` rather than hardcoding Hevy, so the strip that
/// renders one row in v0 renders two once Strava's connector stops being a stub
/// (#35) — the view already loops.
///
/// Freshness is a function rather than a stored property on purpose. The strip
/// re-renders on a timer, and a value that baked in the age at init would keep
/// claiming "23 h" into the next day — the one statement this type exists to
/// make.
struct DataSourceStatus: Equatable, Identifiable {
    let source: ConnectorSource
    /// Last successful sync for this source, or `nil` if none ever completed.
    let lastSync: Date?
    /// Whether a sync for this source is in flight.
    let isSyncing: Bool

    var id: ConnectorSource { source }

    init(source: ConnectorSource, lastSync: Date?, isSyncing: Bool = false) {
        self.source = source
        self.lastSync = lastSync
        self.isSyncing = isSyncing
    }

    /// How current this source is as of `now`.
    func freshness(now: Date) -> DataSourceFreshness {
        DataSourceFreshness(lastSync: lastSync, now: now)
    }

    /// Whether the row should carry the warning treatment and a retry button.
    ///
    /// A sync in flight never does: the answer is already on its way, and a
    /// retry button next to a running spinner invites a second request that
    /// would only be dropped.
    func needsAttention(now: Date) -> Bool {
        !isSyncing && freshness(now: now).needsAttention
    }

    /// The line the row prints after the provider name.
    func summary(now: Date) -> String {
        isSyncing
            ? "Syncing…"
            : SyncTimeFormatter.lastSynced(lastSync, now: now)
    }
}
