import Foundation

/// Persists the timestamp of the last successful Hevy sync.
///
/// `UserDefaults`, not SwiftData: ADR-001 keeps this one scalar out of the
/// store deliberately. It survives app kills so the dashboard can always show
/// how fresh the cached data is (US-2 AC2), even when the sync itself failed.
actor SyncTimestampStore {
    /// Key convention per ADR-001 (`fitbuddy.` namespace).
    private static let lastSyncKey = "fitbuddy.sync.lastSyncTimestamp"

    private let defaults: UserDefaults

    /// - Parameter defaults: Injectable for tests (isolated suite).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Timestamp of the last successful sync, or `nil` if none ever completed.
    func lastSync() -> Date? {
        // `double(forKey:)` returns 0 for a missing key, which is a valid date
        // (1970) — check for the object first to keep "never synced" distinct.
        guard defaults.object(forKey: Self.lastSyncKey) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: Self.lastSyncKey))
    }

    /// Records a successful sync.
    func setLastSync(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastSyncKey)
    }

    /// Drops the timestamp (hard logout, "delete my data").
    func clear() {
        defaults.removeObject(forKey: Self.lastSyncKey)
    }
}
