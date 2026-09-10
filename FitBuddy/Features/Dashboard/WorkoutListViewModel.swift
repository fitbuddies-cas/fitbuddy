import Foundation

/// Drives the dashboard's workout list, its 90-day metrics and the Hevy sync
/// that keeps them current (US-2).
///
/// Everything on screen is rendered from the SwiftData cache — `load()` never
/// touches the network. The sync is a separate step that writes into that same
/// cache and is then read back, so the dashboard renders identically whether
/// the last sync just succeeded or the device has been offline for days
/// (#28 AC1). `lastSync` and `syncStatus` tell the user which of the two it is.
@MainActor
final class WorkoutListViewModel: ObservableObject {
    @Published private(set) var state: WorkoutListState = .loading
    /// Timestamp of the last successful sync, or `nil` if none ever completed
    /// — the banner data for US-2 AC2.
    @Published private(set) var lastSync: Date?
    /// Whether a sync is running and how the last one ended (#28).
    @Published private(set) var syncStatus: SyncStatus = .idle
    /// The failed pull-to-refresh still waiting to be announced, or `nil` when
    /// there is nothing to say (#43). Only ever set by `retry()` — the
    /// automatic sync behind `reload()` has the banner and nothing to confirm.
    @Published private(set) var refreshNotice: RefreshNotice?

    /// Called when the source rejected the stored key, which `WorkoutSyncService` has
    /// already wiped. The dashboard cannot recover from this on its own — the
    /// app has to route back to onboarding (US-1 AC3), which only the root
    /// view can do, so it is handed in as a callback.
    var onUnauthorized: (() async -> Void)?

    /// The sources the status strip reports on (US-8, #40).
    ///
    /// Derived rather than stored: `lastSync` and `syncStatus` are both
    /// published, so SwiftUI re-renders whenever either moves, and a second
    /// copy of the same facts is a second thing that can be wrong. v0 syncs one
    /// source — `WorkoutSyncService` fetches Hevy and nothing else — so the
    /// list holds one entry; a Strava row appears here once its connector stops
    /// throwing `.notImplemented` (#35).
    var dataSources: [DataSourceStatus] {
        [DataSourceStatus(source: .hevy, lastSync: lastSync, isSyncing: syncStatus == .syncing)]
    }

    /// The read currently in flight, so a newer `load()` supersedes it.
    private var loadTask: Task<Void, Never>?
    /// Identifies the read that owns `state`, bumped once per read — the same
    /// distinction `syncGeneration` draws, for the same reason. A read the
    /// sync starts after caching a fresh window is routinely cancelled from
    /// outside, and its result is the whole point of the sync.
    private var loadGeneration = 0
    /// The sync currently in flight, so repeated pull-to-refresh does not
    /// stack up parallel windows fetches on Hevy.
    private var syncTask: Task<Void, Never>?
    /// Identifies the sync that owns `syncStatus`, bumped once per sync.
    ///
    /// `Task.isCancelled` cannot stand in for this. It is true both when a
    /// newer sync superseded this one and when the cancellation came from
    /// outside — SwiftUI tearing down the `.refreshable` task as the user
    /// leaves the tab mid-pull — and the two need opposite responses.
    private var syncGeneration = 0

    private let cache: WorkoutSummaryReading
    private let syncer: WorkoutSyncing?
    private let timestamps: SyncTimestampStore
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - cache: Read access to the cached window (`WorkoutStore` in the app).
    ///   - syncer: Fills that cache from the source (`WorkoutSyncService` in the app).
    ///     Optional so previews and the cache-only tests can leave it out; a
    ///     `nil` syncer makes `refresh()` a plain cache read.
    ///   - now: Injectable clock, so the window boundary is testable.
    init(
        cache: WorkoutSummaryReading,
        syncer: WorkoutSyncing? = nil,
        timestamps: SyncTimestampStore = SyncTimestampStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.cache = cache
        self.syncer = syncer
        self.timestamps = timestamps
        self.calendar = calendar
        self.now = now
    }

    /// The user asked for fresh data: pull-to-refresh, or one of the retry
    /// buttons (#43, US-10 AC1).
    ///
    /// Does the same work as `refresh()` and adds one thing — a failure is
    /// also announced once through `refreshNotice`. The banner alone cannot
    /// carry that: it is already up when the user pulls, and a second failure
    /// of the same kind leaves it looking exactly as it did, so nothing on
    /// screen would confirm that the retry ran at all (US-10 AC2).
    func retry() async {
        await refresh(announcingFailure: true)
    }

    /// The dashboard's own sync, silent about its failures — the banner is
    /// the whole report. `retry()` is the announcing counterpart, and the two
    /// entry points are the only ones: the parametrised body below is private
    /// so a caller cannot end up in the announcing path by accident.
    func refresh() async {
        await refresh(announcingFailure: false)
    }

    /// Drops the toast — its timeout elapsed, or the user tapped it away.
    func dismissRefreshNotice() {
        refreshNotice = nil
    }

    /// Shows what is cached, then brings it up to date from Hevy — the
    /// dashboard's `.task` and its pull-to-refresh.
    ///
    /// The cache read comes first on purpose: an offline device then has the
    /// full dashboard on screen before the request has even timed out, and the
    /// failed sync only adds the banner on top (#28 AC1).
    ///
    /// - Parameter announcingFailure: Raises a `refreshNotice` if the sync
    ///   fails. Only the user-triggered path passes `true` — see `retry()`.
    private func refresh(announcingFailure: Bool) async {
        // An empty cache while the sync behind it is still running is not an
        // answer about the user's training yet: the window may simply have
        // been discarded (#91) or never filled. The spinner stays up and the
        // read after the sync publishes the real answer — only from a resting
        // `.loading`, so pull-to-refresh keeps its content on screen.
        let holdsSpinner = syncer != nil && state == .loading
        await load(keepingSpinnerWhenEmpty: holdsSpinner)
        await sync(announcingFailure: announcingFailure)
    }

    /// The dashboard's own load: its first appearance, and every time another
    /// screen invalidated the cache while it stayed alive (#91).
    ///
    /// Unlike pull-to-refresh it starts from the spinner — the read underneath
    /// a discarded cache returns nothing, and "No training data" would be a
    /// statement about an account this device no longer holds.
    func reload() async {
        state = .loading
        await refresh()
    }

    /// Loads the window from the cache and recomputes the metrics.
    ///
    /// Safe to call again after a sync: the previous content stays on screen
    /// while the read runs, so a refresh never flashes an empty dashboard.
    ///
    /// Overlapping calls — pull-to-refresh landing on top of the initial
    /// `.task` (#27) — cancel the older read, so a slow first result cannot
    /// overwrite a fresher one that already returned.
    ///
    /// - Parameter keepingSpinnerWhenEmpty: Leaves `.loading` up instead of
    ///   publishing `.empty` — for the read that runs before a sync, see
    ///   `refresh()`.
    func load(keepingSpinnerWhenEmpty: Bool = false) async {
        loadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration
        let task = Task {
            await performLoad(
                keepingSpinnerWhenEmpty: keepingSpinnerWhenEmpty,
                generation: generation
            )
        }
        loadTask = task
        await task.awaitingCancellation()
    }

    private func performLoad(keepingSpinnerWhenEmpty: Bool, generation: Int) async {
        let syncedAt = await timestamps.lastSync()

        let windowStart = TrainingWindow.start(endingAt: now(), calendar: calendar)
        let newState: WorkoutListState
        do {
            let summaries = try await cache.workoutSummaries(since: windowStart)
            newState = summaries.isEmpty
                ? (keepingSpinnerWhenEmpty ? .loading : .empty)
                : .loaded(
                    workouts: summaries,
                    metrics: DashboardMetrics(summaries: summaries, calendar: calendar)
                )
        } catch {
            // A read the caller interrupted says nothing about the store, so
            // `.failed` would tell the user their training data is unreadable
            // when it is not. Leave the screen as it is instead.
            guard !error.isCancellation else { return }
            newState = .failed
        }

        // Publish nothing once superseded: the newer read owns `state`, and a
        // slow older result would overwrite what it already published.
        guard isCurrentLoad(generation) else { return }
        lastSync = syncedAt
        state = newState
    }

    // MARK: - Sync

    /// Fetches the window from Hevy into the cache and reads it back.
    ///
    /// Never throws and never clears the screen: a failed sync leaves the
    /// cached dashboard exactly as it was and only sets `syncStatus`.
    private func sync(announcingFailure: Bool) async {
        guard let syncer else { return }
        syncTask?.cancel()
        syncGeneration &+= 1
        let generation = syncGeneration
        let task = Task {
            await performSync(
                with: syncer,
                announcingFailure: announcingFailure,
                generation: generation
            )
        }
        syncTask = task
        await task.awaitingCancellation()
    }

    private func performSync(
        with syncer: WorkoutSyncing,
        announcingFailure: Bool,
        generation: Int
    ) async {
        // Closes the window in which a superseded task publishes `.syncing`
        // over the newer one's result. The main actor runs task bodies FIFO,
        // so this is not reachable today — but it costs one line.
        guard isCurrentSync(generation) else { return }
        syncStatus = .syncing
        do {
            let result = try await syncer.syncRecentWorkouts()
            guard isCurrentSync(generation) else { return }
            // Clears the banner (#28 AC3) before the reload, so the cached
            // window and the "up to date" claim land in the same render pass.
            // The toast goes with it: a message about a failure that has just
            // been made good would contradict the timestamp above it (#43).
            //
            // A partial sync (#143) is neither: the timestamp moved and the
            // data is fresh, but a source is missing from it. `degraded`
            // carries which, per source, for the banner to say so. No toast —
            // the moved timestamp is what tells the user their pull ran.
            syncStatus = Self.status(after: result)
            refreshNotice = nil
            await load()
        } catch {
            // Superseded by a newer sync: that one owns `syncStatus` now, so
            // this one publishes nothing at all — not even the idle reset.
            // Every other way out of this block, cancellation included, has to
            // leave `.syncing` behind it.
            guard isCurrentSync(generation) else { return }

            // A cancelled request says nothing about connectivity, so it gets
            // no banner. It still has to clear `.syncing`, or the strip would
            // claim a sync is running forever.
            guard !error.isCancellation else {
                syncStatus = .idle
                await resolveHeldSpinner()
                return
            }

            guard let failure = SyncFailure(syncError: error) else {
                // The key is gone. The banner would be pointless: the next
                // screen is onboarding, not the dashboard.
                syncStatus = .idle
                refreshNotice = nil
                await onUnauthorized?()
                return
            }
            syncStatus = .failed(failure)
            // US-10 AC2: the toast is what tells the user their pull happened
            // and did not work. Raised after the banner, so both describe the
            // same failure in one render pass.
            if announcingFailure {
                refreshNotice = RefreshNotice(failure: failure)
            }
            await resolveHeldSpinner()
        }
    }

    /// `idle` for a clean sync, `degraded` with one banner reason per failed
    /// source otherwise. A source whose failure has no banner wording (an
    /// auth failure on Hevy would have thrown instead) is left out.
    private static func status(after result: SyncResult) -> SyncStatus {
        var failures: [ConnectorSource: SyncFailure] = [:]
        for (source, error) in result.failures {
            failures[source] = SyncFailure(syncError: error, source: source)
        }
        return failures.isEmpty ? .idle : .degraded(failures: failures)
    }

    /// Whether this read is still the one `state` belongs to. See
    /// `isCurrentSync(_:)` — a read cancelled from outside is still current
    /// and publishes what it found.
    private func isCurrentLoad(_ generation: Int) -> Bool {
        generation == loadGeneration
    }

    /// Whether this sync is still the one `syncStatus` belongs to.
    ///
    /// False only once a newer sync has taken over, which is the single case
    /// where staying silent is right — the newer one publishes instead. A sync
    /// that was cancelled from outside is still the current one, so it reports
    /// its outcome and clears the spinner on its way out.
    private func isCurrentSync(_ generation: Int) -> Bool {
        generation == syncGeneration
    }

    /// Publishes the empty state that the pre-sync read held back when the
    /// sync itself had no reload to do — otherwise the spinner would sit on
    /// screen forever over an empty cache (#28 AC1, #91).
    ///
    /// Only reached after the caller has ruled out being superseded, so this
    /// never cancels a newer read.
    private func resolveHeldSpinner() async {
        guard case .loading = state else { return }
        await load()
    }
}
