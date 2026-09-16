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
/// The LLM keys are deliberately kept. They are separate credentials that
/// Hevy did not reject, and re-entering them is a needless detour through
/// onboarding step 3. The Strava and Polar connections are *not* kept on a
/// hard logout:
/// the session is over and the app is back in onboarding, and whoever walks
/// through it next — possibly another person the device was handed to, the
/// case US-1 AC3 exists for — must not find the previous user's Strava or
/// Polar history and a live token pair for their account behind it.
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

    /// Ends the session: the Hevy key, the Strava and Polar credentials and
    /// tokens, and every cached session of all three go. Never throws: a logout that fails
    /// halfway is worse than one that reports its problems to the log, and
    /// the caller is already handling an auth error it must surface either
    /// way. Each step is independent, so one failure does not skip the others.
    func hardLogout() async {
        for key in [KeychainKey.hevyAPIKey] + StravaCredentialStore.ownedKeys
            + PolarCredentialStore.ownedKeys {
            do {
                try await keychain.delete(key)
            } catch {
                logger.error("\(key.rawValue, privacy: .public) not deleted on logout: \(error, privacy: .public)")
            }
        }
        await discardCachedWorkouts()
        await discardCachedWorkouts(from: .strava)
        await discardCachedWorkouts(from: .polar)
    }

    /// Drops the cached Hevy workouts and the sync timestamp, keeping the
    /// stored key — what replacing the Hevy key in Settings needs (#91).
    ///
    /// Only Hevy's sessions go (#141): a second source's cache describes a
    /// connection this reset is not about, and the user would otherwise watch
    /// their Strava history vanish because their Hevy key changed.
    ///
    /// The timestamp goes with the cache, always: a "last synced 5 min ago"
    /// line over an empty dashboard describes a sync of somebody else's
    /// account, and leaving it behind would also let a delta sync believe it
    /// only has to fetch what changed since then.
    ///
    /// The whole analysis history goes too (#97, #117): every one of those
    /// texts was written about the workouts being discarded here, and showing
    /// them over the next account's dashboard would present one Hevy account's
    /// training as advice for another's. The rate-limit timestamp deliberately
    /// stays — this is not a deletion request, and clearing it would make a
    /// logout a way around the lock.
    func discardCachedWorkouts() async {
        await discardCachedWorkouts(from: .hevy)
        do {
            try await results.deleteAll()
        } catch {
            logger.error("Stored analysis not cleared: \(error, privacy: .public)")
        }
        await timestamps.clear()
    }

    /// Drops one source's cached sessions and nothing else (#140).
    ///
    /// Unlike the Hevy teardown above, the analysis history and the sync
    /// timestamp stay: disconnecting Strava removes a part of the user's own
    /// training from view, it does not swap one account for another, and the
    /// recommendations were written about training that remains theirs.
    func discardCachedWorkouts(from source: ConnectorSource) async {
        do {
            try await workouts.deleteCachedWorkouts(from: source)
        } catch {
            logger.error("\(source.displayName, privacy: .public) cache not cleared: \(error, privacy: .public)")
        }
    }
}
