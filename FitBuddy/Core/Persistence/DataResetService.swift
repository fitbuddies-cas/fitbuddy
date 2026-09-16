import Foundation
import OSLog

/// Removes every trace of the user's data from this device — the "Delete all
/// data" action in Settings (#83) and the deletion right the privacy policy
/// promises.
///
/// Wipes all Keychain items (every API key, the Strava credentials *and* the
/// consent metadata, so consent is asked for again per US-4 AC5), the
/// SwiftData workout cache, the whole analysis history, the sync timestamp,
/// the LLM priority order, the step-3 skip marker and the legacy timestamp of
/// the removed analysis lock. The connectors' in-memory copies of the keys are
/// not reachable from here; `WorkoutSyncService` drops them on the next sync
/// when it finds the stored ones gone.
///
/// Deliberately kept: `FirstLaunchResetService`'s marker. It records the
/// installation, not the session — clearing it would only trigger a redundant
/// (and idempotent) Keychain purge on the next launch.
///
/// Same shape as `SessionResetService`: never throws, every step independent,
/// failures logged. A reset that stops halfway leaves the user with data they
/// asked to be rid of and no way to retry the remaining steps.
actor DataResetService {
    private let keychain: any KeychainStoring
    private let workouts: WorkoutStore
    private let results: AnalysisResultStore
    private let timestamps: SyncTimestampStore
    private let priority: LLMPriorityStore
    private let skip: LLMKeysSkipStore
    private let defaults: UserDefaults

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "DataReset")

    init(
        keychain: any KeychainStoring = KeychainService(),
        workouts: WorkoutStore,
        results: AnalysisResultStore,
        timestamps: SyncTimestampStore = SyncTimestampStore(),
        priority: LLMPriorityStore = LLMPriorityStore(),
        skip: LLMKeysSkipStore = LLMKeysSkipStore(),
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.workouts = workouts
        self.results = results
        self.timestamps = timestamps
        self.priority = priority
        self.skip = skip
        self.defaults = defaults
    }

    /// Where the removed 60s analysis lock (#117) stored its last call. Nothing
    /// reads it any more; it is only deleted, so "delete all data" leaves no
    /// trace of it on devices that ran a build with the lock.
    static let legacyAnalysisLockKey = "fitbuddy.analysis.lastCallTimestamp"

    /// Deletes all locally stored data. Never throws — see the type comment.
    func deleteAllData() async {
        for key in KeychainKey.allCases {
            do {
                try await keychain.delete(key)
            } catch {
                logger.error("Keychain item \(key.rawValue, privacy: .public) not deleted: \(error, privacy: .public)")
            }
        }
        do {
            try await workouts.deleteAll()
        } catch {
            logger.error("Workout cache not cleared: \(error, privacy: .public)")
        }
        do {
            try await results.deleteAll()
        } catch {
            logger.error("Analysis history not cleared: \(error, privacy: .public)")
        }
        await timestamps.clear()
        // Legacy from #117: the analysis lock is gone, its timestamp may not be.
        defaults.removeObject(forKey: Self.legacyAnalysisLockKey)
        await priority.clear()
        await skip.clear()
    }
}
