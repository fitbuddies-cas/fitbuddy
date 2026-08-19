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

    /// Called when Hevy rejected the stored key, which `HevyService` has
    /// already wiped. The dashboard cannot recover from this on its own — the
    /// app has to route back to onboarding (US-1 AC3), which only the root
    /// view can do, so it is handed in as a callback.
    var onUnauthorized: (() async -> Void)?

    /// The read currently in flight, so a newer `load()` supersedes it.
    private var loadTask: Task<Void, Never>?
    /// The sync currently in flight, so repeated pull-to-refresh does not
    /// stack up parallel windows fetches on Hevy.
    private var syncTask: Task<Void, Never>?

    private let cache: WorkoutSummaryReading
    private let syncer: WorkoutSyncing?
    private let timestamps: SyncTimestampStore
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - cache: Read access to the cached window (`WorkoutStore` in the app).
    ///   - syncer: Fills that cache from Hevy (`HevyService` in the app).
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

    /// Shows what is cached, then brings it up to date from Hevy — the
    /// dashboard's `.task` and its pull-to-refresh.
    ///
    /// The cache read comes first on purpose: an offline device then has the
    /// full dashboard on screen before the request has even timed out, and the
    /// failed sync only adds the banner on top (#28 AC1).
    func refresh() async {
        await load()
        await sync()
    }

    /// Loads the window from the cache and recomputes the metrics.
    ///
    /// Safe to call again after a sync: the previous content stays on screen
    /// while the read runs, so a refresh never flashes an empty dashboard.
    ///
    /// Overlapping calls — pull-to-refresh landing on top of the initial
    /// `.task` (#27) — cancel the older read, so a slow first result cannot
    /// overwrite a fresher one that already returned.
    func load() async {
        loadTask?.cancel()
        let task = Task { await performLoad() }
        loadTask = task
        await task.awaitingCancellation()
    }

    private func performLoad() async {
        let syncedAt = await timestamps.lastSync()

        let windowStart = TrainingWindow.start(endingAt: now(), calendar: calendar)
        let newState: WorkoutListState
        do {
            let summaries = try await cache.workoutSummaries(since: windowStart)
            newState = summaries.isEmpty
                ? .empty
                : .loaded(
                    workouts: summaries,
                    metrics: DashboardMetrics(summaries: summaries, calendar: calendar)
                )
        } catch {
            newState = .failed
        }

        // Publish nothing once superseded: a cancelled read's result is stale
        // by definition, and `.failed` from a cancelled read would be a lie.
        guard !Task.isCancelled else { return }
        lastSync = syncedAt
        state = newState
    }

    // MARK: - Sync

    /// Fetches the window from Hevy into the cache and reads it back.
    ///
    /// Never throws and never clears the screen: a failed sync leaves the
    /// cached dashboard exactly as it was and only sets `syncStatus`.
    private func sync() async {
        guard let syncer else { return }
        syncTask?.cancel()
        let task = Task { await performSync(with: syncer) }
        syncTask = task
        await task.awaitingCancellation()
    }

    private func performSync(with syncer: WorkoutSyncing) async {
        // Closes the window in which a superseded task publishes `.syncing`
        // over the newer one's result. The main actor runs task bodies FIFO,
        // so this is not reachable today — but it costs one line.
        guard !Task.isCancelled else { return }
        syncStatus = .syncing
        do {
            try await syncer.syncRecentWorkouts()
            guard !Task.isCancelled else { return }
            // Clears the banner (#28 AC3) before the reload, so the cached
            // window and the "up to date" claim land in the same render pass.
            syncStatus = .idle
            await load()
        } catch {
            // Superseded by a newer sync: that one owns `syncStatus` now, so
            // this one publishes nothing at all — not even the idle reset.
            guard !Task.isCancelled else { return }

            // A cancelled request says nothing about connectivity, so it gets
            // no banner. It still has to clear `.syncing`, or the strip would
            // claim a sync is running forever.
            guard !Self.isCancellation(error) else {
                syncStatus = .idle
                return
            }

            guard let failure = SyncFailure(syncError: error) else {
                // The key is gone. The banner would be pointless: the next
                // screen is onboarding, not the dashboard.
                syncStatus = .idle
                await onUnauthorized?()
                return
            }
            syncStatus = .failed(failure)
        }
    }

    /// `URLSession` reports a cancelled request as `URLError.cancelled`, not as
    /// `CancellationError`, so both forms have to be recognised.
    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

private extension Task where Success == Void, Failure == Never {
    /// Awaits the task, forwarding the caller's cancellation into it.
    ///
    /// The task has to stay unstructured — a newer `load()` or `sync()`
    /// cancels the older one by holding on to it, which a child task would not
    /// allow. But unstructured also means SwiftUI tearing down the `.task` that
    /// started it leaves the work running: the request finishes, the result is
    /// published to a view nobody is looking at. This bridges the two.
    func awaitingCancellation() async {
        await withTaskCancellationHandler {
            await value
        } onCancel: {
            cancel()
        }
    }
}
