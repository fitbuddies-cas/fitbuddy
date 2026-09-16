import Foundation
import OSLog

/// Loads the dashboard's 90-day workout window from every connected
/// `FitnessConnector` (US-2, US-5) and caches it locally, one source at a time.
///
/// Everything the providers know about lives in their connectors (ADR-6);
/// what stays here is what belongs to the app's session rather than to a
/// source: the stored credentials, the window boundary, the local cache, the
/// sync timestamp, and the hard logout US-1 AC3 demands on a rejected Hevy
/// key. The connectors themselves come from the `ConnectorRegistry` (#143),
/// so the sync names no provider type — only `ConnectorSource`.
///
/// **Partial results rather than a total failure.** Sources are fetched in
/// parallel and cached one after another; a source that fails is recorded in
/// `SyncResult.failures` and the others still land. The sync throws only when
/// every connected source failed — or when Hevy rejected its key, because that
/// ends the session whatever Strava did (ADR-6, addendum to #35, point 3).
actor WorkoutSyncService: WorkoutSyncing {
    private let registry: ConnectorRegistry
    private let keychain: KeychainService
    private let stravaCredentials: any StravaCredentialStoring
    private let polarCredentials: any PolarCredentialStoring
    private let workouts: WorkoutStore
    private let timestamps: SyncTimestampStore
    private let sessionReset: SessionResetService
    private let calendar: Calendar
    private let now: () -> Date

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "WorkoutSyncService")

    /// - Parameters:
    ///   - registry: Holds the connectors. Hevy has to be registered; Strava
    ///     is synced when it is registered *and* has stored credentials.
    ///   - stravaCredentials: Where the Strava token pair comes from. Hevy's
    ///     key comes from `keychain` directly, as before.
    ///   - polarCredentials: Where the Polar token pair comes from (#159).
    ///   - sessionReset: Defaults to one built from the other dependencies —
    ///     it cannot be a default argument because it needs them.
    ///   - now: Injectable clock, so window boundaries are testable.
    init(
        registry: ConnectorRegistry,
        keychain: KeychainService = KeychainService(),
        stravaCredentials: any StravaCredentialStoring = StravaCredentialStore(),
        polarCredentials: any PolarCredentialStoring = PolarCredentialStore(),
        workouts: WorkoutStore,
        timestamps: SyncTimestampStore = SyncTimestampStore(),
        sessionReset: SessionResetService? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.registry = registry
        self.keychain = keychain
        self.stravaCredentials = stravaCredentials
        self.polarCredentials = polarCredentials
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
        // Hevy first and on its own terms: without its key the app is not
        // onboarded, and that is a thrown error, not a per-source failure.
        let hevyKey = try await storedHevyKey()
        let syncedAt = now()
        let windowStart = TrainingWindow.start(endingAt: syncedAt, calendar: calendar)

        var failures: [ConnectorSource: WorkoutSyncError] = [:]
        var credentials: [ConnectorSource: ConnectorCredentials] = [.hevy: .apiKey(hevyKey)]
        // `allCases` order, so "the first source" below means the same thing
        // on every run.
        var sources: [ConnectorSource] = [.hevy]
        switch await storedStravaCredentials() {
        case .available(let pair):
            credentials[.strava] = pair
            sources.append(.strava)
        case .unreadable:
            // A Keychain that refuses the read cannot say whether a pair is
            // in there. Only a connection this process already knows about
            // makes that a Strava failure worth a banner; on a device that
            // never connected Strava it would announce a source the user
            // does not have. Either way it is an attempted source, so the
            // result lists it (`SyncResult.sources`).
            if await registry.state(of: .strava, now: syncedAt) != .disconnected {
                failures[.strava] = .keychainUnavailable
                sources.append(.strava)
            }
        case .notConfigured:
            // No pair stored — disconnected by the user, or wiped by "delete
            // all data" (#83), which knows nothing about the connector. Same
            // rule as for the Hevy key in `storedHevyKey()`: a reset the UI
            // promises is a full deletion must not leave the tokens sitting in
            // the process.
            await registry.disconnect(.strava)
        }
        switch await storedPolarCredentials() {
        case .available(let pair):
            credentials[.polar] = pair
            sources.append(.polar)
        case .unreadable:
            // Same rule as for Strava above.
            if await registry.state(of: .polar, now: syncedAt) != .disconnected {
                failures[.polar] = .keychainUnavailable
                sources.append(.polar)
            }
        case .notConfigured:
            await registry.disconnect(.polar)
        }
        logger.notice("Fetching \(sources.map(\.rawValue).joined(separator: ","), privacy: .public); task cancelled: \(Task.isCancelled, privacy: .public)")

        let outcomes = await fetchWindows(from: windowStart, credentials: credentials, sources: sources)
        for source in sources {
            guard case .failure(let error)? = outcomes[source] else {
                if case .success(let activities)? = outcomes[source] {
                    logger.notice("\(source.rawValue, privacy: .public): \(activities.count, privacy: .public) activities")
                }
                continue
            }
            logger.notice("\(source.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            guard let syncError = error as? WorkoutSyncError else {
                // Anything that is not a `WorkoutSyncError` travels out
                // untouched — in practice a cancellation: navigating away
                // mid-sync must not surface as "no internet".
                throw error
            }
            failures[source] = syncError
        }

        // A rejected Hevy key ends the session whatever the other sources did:
        // the hard logout has already run, and the caller has to route back
        // to onboarding (US-1 AC3). A partial result would hide that.
        if failures[.hevy] == .unauthorized {
            throw WorkoutSyncError.unauthorized
        }

        // The fetch took seconds, and a sync outlives the gesture that started
        // it (#150) — so the user may have confirmed "delete Hevy key" or
        // "delete all data" (#83) in the meantime. Both resets remove the key
        // before they empty the cache, so a key that is gone now means the
        // windows in hand belong to a session that has ended. Caching them
        // would restore exactly the data the user just deleted (US-1 AC3).
        //
        // Thrown as a cancellation on purpose: for the dashboard this sync
        // ends the way one cancelled from outside does — nothing to show,
        // nothing to report, and the app is already on its way to onboarding.
        // `.missingAPIKey` would make it route there a second time, with a
        // "key rejected" notice for a key the user removed themselves.
        guard await sessionIsStillOpen() else {
            // Both resets that remove the Hevy key take the Strava and Polar
            // pairs with it (`SessionResetService.hardLogout()`, `DataResetService`).
            await registry.disconnect(.hevy)
            await registry.disconnect(.strava)
            await registry.disconnect(.polar)
            throw CancellationError()
        }

        var cachedCount = 0
        for source in sources {
            guard case .success(let activities)? = outcomes[source] else { continue }
            do {
                try await workouts.replaceCachedWorkouts(from: source, with: activities)
                cachedCount += activities.count
            } catch {
                logger.error("Caching \(activities.count) \(source.displayName, privacy: .public) activities failed: \(error, privacy: .public)")
                failures[source] = .persistenceFailed
            }
        }

        // Nothing landed: the timestamp stays untouched, so the dashboard
        // keeps advertising the older sync (US-2 AC2), and the first source's
        // failure is the one reported.
        guard sources.contains(where: { failures[$0] == nil }) else {
            throw sources.compactMap { failures[$0] }.first ?? WorkoutSyncError.invalidResponse
        }

        await timestamps.setLastSync(syncedAt)
        return SyncResult(
            workoutCount: cachedCount,
            syncedAt: syncedAt,
            windowStart: windowStart,
            failures: failures,
            sources: sources
        )
    }

    // MARK: - Connectors

    /// Asks every source for its window at the same time. The connectors are
    /// actors of their own, so the requests overlap; the cache writes that
    /// follow are sequential, since one `ModelActor` owns the store.
    private func fetchWindows(
        from windowStart: Date,
        credentials: [ConnectorSource: ConnectorCredentials],
        sources: [ConnectorSource]
    ) async -> [ConnectorSource: Result<[Activity], Error>] {
        await withTaskGroup(of: (ConnectorSource, Result<[Activity], Error>).self) { group in
            for source in sources {
                guard let pair = credentials[source] else { continue }
                group.addTask {
                    do {
                        return (source, .success(try await self.fetchWindow(for: source, credentials: pair, from: windowStart)))
                    } catch {
                        return (source, .failure(error))
                    }
                }
            }
            var outcomes: [ConnectorSource: Result<[Activity], Error>] = [:]
            for await (source, outcome) in group {
                outcomes[source] = outcome
            }
            return outcomes
        }
    }

    /// Hands the credentials to the source's connector through the registry
    /// and asks it for the window.
    ///
    /// The `ConnectorError` the connector may throw is translated here, and
    /// only here. `unauthorized` is the one case with a side effect, and it
    /// depends on the source: Hevy's session is over, so the hard logout runs
    /// (US-1 AC3); Strava's pair stays where it is, because only the user can
    /// renew it and the dashboard has to be able to say so (US-5 AC2).
    private func fetchWindow(
        for source: ConnectorSource,
        credentials: ConnectorCredentials,
        from windowStart: Date
    ) async throws -> [Activity] {
        do {
            // `IfNewer`: a pair the connector refreshed since the last sync
            // must not be replaced by the stored one — see the comment after
            // the fetch.
            try await registry.connectIfNewer(source, credentials: credentials)
            guard let connector = await registry.connector(for: source) else {
                throw ConnectorRegistryError.notRegistered(source)
            }
            let activities = try await connector.fetchActivities(since: windowStart)

            // An OAuth fetch (Strava, Polar) may have refreshed the pair on the
            // way; the registry's expiry bookkeeping has to follow the rotated
            // pair, or it would prompt for a renewal the connector already did. Only a
            // pair *newer* than the one recorded is taken: each connector
            // tolerates a persist that failed (locked Keychain) and keeps the
            // rotated pair in memory, and re-connecting it with the stale
            // stored pair would make every later refresh in this process send
            // a refresh token the provider has already invalidated.
            if source == .strava, case .available(let fresh) = await storedStravaCredentials() {
                try? await registry.connectIfNewer(.strava, credentials: fresh)
            }
            if source == .polar, case .available(let fresh) = await storedPolarCredentials() {
                try? await registry.connectIfNewer(.polar, credentials: fresh)
            }
            return activities
        } catch let error as ConnectorError {
            if error == .unauthorized, source == .hevy {
                // The stored key was revoked — drop it and the cached data
                // before the caller routes back to onboarding. The logout
                // takes the Strava and Polar pairs with it (US-1 AC3), so the
                // connectors' copies go too.
                await registry.disconnect(.hevy)
                await registry.disconnect(.strava)
                await registry.disconnect(.polar)
                await sessionReset.hardLogout()
            }
            throw WorkoutSyncError(connectorError: error)
        } catch let error as ConnectorRegistryError {
            // No connector behind the source: a composition mistake, not a
            // provider failure. Reported as the source not being able to sync.
            logger.error("Sync skipped: \(String(describing: error), privacy: .public)")
            throw WorkoutSyncError.notImplemented
        }
    }

    // MARK: - Credentials

    /// Whether the stored key is still there — re-checked right before the
    /// cache write, see `syncRecentWorkouts()`.
    ///
    /// Only a definite "gone" voids the sync. A Keychain that refuses the read
    /// (locked device) still holds the key the window was fetched under, so
    /// the write goes ahead — the same distinction `storedAPIKey()` draws
    /// between `.missingAPIKey` and `.keychainUnavailable`.
    private func sessionIsStillOpen() async -> Bool {
        do {
            let stored = try await keychain.read(.hevyAPIKey)
            return !(stored ?? "").isEmpty
        } catch {
            return true
        }
    }

    private func storedHevyKey() async throws -> String {
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
            await registry.disconnect(.hevy)
            await registry.disconnect(.strava)
            await registry.disconnect(.polar)
            throw WorkoutSyncError.missingAPIKey
        }
        return key
    }

    /// Outcome of reading an optional OAuth source's stored pair — shared by
    /// Strava and Polar, both of which are connected only when the user
    /// chose to.
    private enum StoredOAuthCredentials {
        case available(ConnectorCredentials)
        case notConfigured
        case unreadable
    }

    /// Strava is optional: no stored pair means the source is simply not
    /// connected, whereas a Keychain that refuses the read is a failure the
    /// result should carry.
    private func storedStravaCredentials() async -> StoredOAuthCredentials {
        do {
            return try await stravaCredentials.credentials().map { .available($0) } ?? .notConfigured
        } catch {
            logger.error("Strava credentials unreadable: \(error, privacy: .public)")
            return .unreadable
        }
    }

    /// Polar is optional the same way Strava is (#159): no stored pair means
    /// not connected, an unreadable Keychain is a failure the result carries.
    private func storedPolarCredentials() async -> StoredOAuthCredentials {
        do {
            return try await polarCredentials.credentials().map { .available($0) } ?? .notConfigured
        } catch {
            logger.error("Polar credentials unreadable: \(error, privacy: .public)")
            return .unreadable
        }
    }
}
