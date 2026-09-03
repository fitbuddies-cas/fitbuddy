import Foundation

/// Abstraction over `SessionResetService` so `SettingsViewModel` can be tested
/// without a SwiftData container, and so a test can observe that the hard
/// logout actually ran.
protocol SessionResetting: Sendable {
    /// Deletes the Hevy key and everything cached under it (US-1 AC3).
    func hardLogout() async

    /// Drops the cached workouts and the sync timestamp but keeps the key —
    /// the Hevy key was replaced, not lost (#91).
    func discardCachedWorkouts() async
}

extension SessionResetService: SessionResetting {}
