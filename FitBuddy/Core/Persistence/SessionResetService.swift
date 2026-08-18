import Foundation
import OSLog

/// Performs the hard logout required when Hevy rejects the stored key
/// (US-1 AC3): the key is deleted, the cached workouts are dropped, and the
/// sync timestamp is cleared.
///
/// Dropping the cache is the point of "hard": ARCHITECTURE.md rules out
/// silently continuing on data the user would read as current — stale training
/// data would otherwise feed a wrong AI recommendation (US-3).
///
/// The Claude key is deliberately kept. It is a separate credential that Hevy
/// did not reject, and re-entering it is a needless detour through onboarding
/// step 3.
actor SessionResetService {
    private let keychain: KeychainService
    private let workouts: WorkoutStore
    private let timestamps: SyncTimestampStore

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "SessionReset")

    init(
        keychain: KeychainService = KeychainService(),
        workouts: WorkoutStore,
        timestamps: SyncTimestampStore = SyncTimestampStore()
    ) {
        self.keychain = keychain
        self.workouts = workouts
        self.timestamps = timestamps
    }

    /// Clears the Hevy session. Never throws: a logout that fails halfway is
    /// worse than one that reports its problems to the log, and the caller is
    /// already handling an auth error it must surface either way. Each step is
    /// independent, so one failure does not skip the others.
    func hardLogout() async {
        do {
            try await keychain.delete(.hevyAPIKey)
        } catch {
            logger.error("Hevy key not deleted on logout: \(error, privacy: .public)")
        }
        do {
            try await workouts.deleteAll()
        } catch {
            logger.error("Workout cache not cleared on logout: \(error, privacy: .public)")
        }
        await timestamps.clear()
    }
}
