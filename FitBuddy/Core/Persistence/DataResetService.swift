import Foundation
import OSLog

/// Removes every trace of the user's data from this device — the "Delete all
/// data" action in Settings (#83) and the deletion right the privacy policy
/// promises.
///
/// Wipes all Keychain items (both API keys *and* the consent metadata, so
/// consent is asked for again per US-4 AC5), the SwiftData workout cache, the
/// sync timestamp, the LLM priority order and the step-3 skip marker.
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
    private let timestamps: SyncTimestampStore
    private let priority: LLMPriorityStore
    private let skip: LLMKeysSkipStore

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "DataReset")

    init(
        keychain: any KeychainStoring = KeychainService(),
        workouts: WorkoutStore,
        timestamps: SyncTimestampStore = SyncTimestampStore(),
        priority: LLMPriorityStore = LLMPriorityStore(),
        skip: LLMKeysSkipStore = LLMKeysSkipStore()
    ) {
        self.keychain = keychain
        self.workouts = workouts
        self.timestamps = timestamps
        self.priority = priority
        self.skip = skip
    }

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
        await timestamps.clear()
        await priority.clear()
        await skip.clear()
    }
}
