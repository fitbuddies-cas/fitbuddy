import Foundation
import OSLog

/// Ends a Hevy session: the hard logout required when Hevy rejects the stored
/// key (US-1 AC3), and the cache teardown on its own for the case where the
/// key is replaced rather than lost (#91).
///
/// Dropping the cache is the point of "hard": ARCHITECTURE.md rules out
/// silently continuing on data the user would read as current — stale training
/// data would otherwise feed a wrong AI recommendation (US-3). That reasoning
/// does not depend on *why* the old key is gone, which is why the teardown is
/// its own entry point rather than something the settings screen rebuilds.
///
/// The Claude key is deliberately kept. It is a separate credential that Hevy
/// did not reject, and re-entering it is a needless detour through onboarding
/// step 3.
actor SessionResetService {
    private let keychain: KeychainService
    private let workouts: WorkoutStore
    private let results: AnalysisResultStore
    private let timestamps: SyncTimestampStore

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "SessionReset")

    /// - Parameter results: The stored AI recommendation, dropped with the
    ///   cache it was derived from (#97).
    init(
        keychain: KeychainService = KeychainService(),
        workouts: WorkoutStore,
        results: AnalysisResultStore,
        timestamps: SyncTimestampStore = SyncTimestampStore()
    ) {
        self.keychain = keychain
        self.workouts = workouts
        self.results = results
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
        await discardCachedWorkouts()
    }

    /// Drops the cached workouts and the sync timestamp, keeping the stored
    /// key — what replacing the Hevy key in Settings needs (#91).
    ///
    /// The timestamp goes with the cache, always: a "last synced 5 min ago"
    /// line over an empty dashboard describes a sync of somebody else's
    /// account, and leaving it behind would also let a delta sync believe it
    /// only has to fetch what changed since then.
    ///
    /// The stored recommendation goes too (#97): it was written about the
    /// workouts being discarded here, and restoring it over the next account's
    /// dashboard would present one Hevy account's training as advice for
    /// another's. The cooldown deliberately stays — this is not a deletion
    /// request, and clearing it would let a logout buy a fresh 6h window.
    func discardCachedWorkouts() async {
        do {
            try await workouts.deleteAll()
        } catch {
            logger.error("Workout cache not cleared: \(error, privacy: .public)")
        }
        do {
            try await results.deleteAll()
        } catch {
            logger.error("Stored analysis not cleared: \(error, privacy: .public)")
        }
        await timestamps.clear()
    }
}
