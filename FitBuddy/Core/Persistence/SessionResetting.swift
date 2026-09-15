import Foundation

/// Abstraction over `SessionResetService` so `SettingsViewModel` can be tested
/// without a SwiftData container, and so a test can observe that the hard
/// logout actually ran.
protocol SessionResetting: Sendable {
    /// Ends the session: deletes the Hevy key, the Strava credentials and
    /// everything cached under either (US-1 AC3).
    func hardLogout() async

    /// Drops the cached Hevy workouts and the sync timestamp but keeps the
    /// key — the Hevy key was replaced, not lost (#91).
    func discardCachedWorkouts() async

    /// Drops one source's cached workouts and nothing else — disconnecting
    /// Strava (#140) must leave the Hevy session, the timestamp and the
    /// analysis history alone.
    func discardCachedWorkouts(from source: ConnectorSource) async
}

extension SessionResetService: SessionResetting {}
