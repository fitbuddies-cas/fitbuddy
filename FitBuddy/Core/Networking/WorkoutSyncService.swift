import Foundation
import OSLog

/// Loads the dashboard's 90-day workout window from a `FitnessConnector`
/// (US-2) and caches it locally.
///
/// Everything the provider knows about lives in the connector (ADR-6, #34);
/// what stays here is what belongs to the app's session rather than to the
/// source: the stored credentials, the window boundary, the local cache, the
/// sync timestamp, and the hard logout US-1 AC3 demands on a rejected key.
/// The type therefore names no provider — swapping `HevyConnector` for a
/// future `StravaConnector` (#35) is a different argument, not a different
/// sync.
actor WorkoutSyncService: WorkoutSyncing {
    private let connector: any FitnessConnector
    private let keychain: KeychainService
    private let workouts: WorkoutStore
    private let timestamps: SyncTimestampStore
    private let sessionReset: SessionResetService
    private let calendar: Calendar
    private let now: () -> Date

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "WorkoutSyncService")

    /// - Parameters:
    ///   - connector: The data source. Defaults to Hevy, the only one v0 ships.
    ///   - sessionReset: Defaults to one built from the other dependencies —
    ///     it cannot be a default argument because it needs them.
    ///   - now: Injectable clock, so window boundaries are testable.
    init(
        connector: any FitnessConnector = HevyConnector(),
        keychain: KeychainService = KeychainService(),
        workouts: WorkoutStore,
        timestamps: SyncTimestampStore = SyncTimestampStore(),
        sessionReset: SessionResetService? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.connector = connector
        self.keychain = keychain
        self.workouts = workouts
        self.timestamps = timestamps
        self.sessionReset = sessionReset
            ?? SessionResetService(
                keychain: keychain,
                workouts: workouts,
                // The same container the workouts live in, so the logout drops
                // the stored recommendation along with the cache it describes
                // (#97).
                results: AnalysisResultStore(modelContainer: workouts.modelContainer),
                timestamps: timestamps
            )
        self.calendar = calendar
        self.now = now
    }

    // MARK: - WorkoutSyncing

    @discardableResult
    func syncRecentWorkouts() async throws -> SyncResult {
        let apiKey = try await storedAPIKey()
        let syncedAt = now()
        let windowStart = TrainingWindow.start(endingAt: syncedAt, calendar: calendar)

        let fetched = try await fetchWindow(from: windowStart, apiKey: apiKey)

        do {
            try await workouts.replaceCachedWorkouts(with: fetched)
        } catch {
            // The timestamp stays untouched: nothing new was cached, so the
            // dashboard must keep advertising the older sync (US-2 AC2).
            logger.error("Caching \(fetched.count) activities failed: \(error, privacy: .public)")
            throw WorkoutSyncError.persistenceFailed
        }

        await timestamps.setLastSync(syncedAt)
        return SyncResult(workoutCount: fetched.count, syncedAt: syncedAt, windowStart: windowStart)
    }

    // MARK: - Connector

    /// Hands the stored key to the connector and asks it for the window.
    ///
    /// The `ConnectorError` the connector may throw is translated here, and
    /// only here: `unauthorized` additionally runs the hard logout, because
    /// wiping the app's session is not the provider's business (US-1 AC3).
    private func fetchWindow(from windowStart: Date, apiKey: String) async throws -> [Activity] {
        do {
            try await connector.connect(credentials: .apiKey(apiKey))
            return try await connector.fetchActivities(since: windowStart)
        } catch let error as ConnectorError {
            if error == .unauthorized {
                // The stored key was revoked — drop it and the cached data
                // before the caller routes back to onboarding.
                await connector.disconnect()
                await sessionReset.hardLogout()
            }
            throw WorkoutSyncError(connectorError: error)
        }
        // Anything that is not a `ConnectorError` travels out untouched — in
        // practice a cancellation: navigating away mid-sync must not surface
        // as "no internet".
    }

    // MARK: - Helpers

    private func storedAPIKey() async throws -> String {
        let stored: String?
        do {
            stored = try await keychain.read(.hevyAPIKey)
        } catch {
            // `KeychainService.read` returns nil for a missing item and only
            // throws for real Keychain failures — e.g. `errSecInteractionNotAllowed`
            // on a locked device, where the key is present but unreadable.
            // Reporting that as `.missingAPIKey` would send a fully onboarded
            // user back to re-enter a key that never went away.
            logger.error("Keychain read failed: \(error, privacy: .public)")
            throw WorkoutSyncError.keychainUnavailable
        }
        guard let key = stored, !key.isEmpty else {
            // The key is gone — a hard logout, or "delete all data" from
            // settings. Neither knows about the connector, so this is where its
            // in-memory copy gets dropped: a reset the UI promises is a full
            // deletion must not leave the key sitting in the process.
            await connector.disconnect()
            throw WorkoutSyncError.missingAPIKey
        }
        return key
    }
}
