import XCTest
@testable import FitBuddy

/// Unit tests for `WorkoutListViewModel` (issue #26): cache-only reads, the
/// 90-day window and the metrics it exposes to the dashboard.
@MainActor
final class WorkoutListViewModelTests: XCTestCase {
    private var cache: StubWorkoutCache!
    private var syncer: StubWorkoutSyncer!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var timestamps: SyncTimestampStore!

    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() async throws {
        try await super.setUp()
        cache = StubWorkoutCache()
        syncer = StubWorkoutSyncer()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        timestamps = SyncTimestampStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        cache = nil
        syncer = nil
        timestamps = nil
        defaults = nil
        try await super.tearDown()
    }

    func testStartsLoading() {
        XCTAssertEqual(makeSUT().state, .loading)
    }

    func testLoadReadsTheCacheForTheLast90Days() async {
        cache.summaries = [summary(id: "w-1", daysAgo: 1, volume: 1000)]

        let sut = makeSUT()
        await sut.load()

        XCTAssertEqual(cache.callCount, 1)
        XCTAssertEqual(cache.requestedSince, TrainingWindow.start(endingAt: reference))
    }

    func testLoadExposesWorkoutsAndMetrics() async {
        cache.summaries = [
            summary(id: "w-1", daysAgo: 1, volume: 1000),
            summary(id: "w-2", daysAgo: 4, volume: 500),
        ]

        let sut = makeSUT()
        await sut.load()

        guard case let .loaded(workouts, metrics) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(workouts.map(\.id), ["w-1", "w-2"])
        XCTAssertEqual(metrics.totalVolumeKg, 1500, accuracy: 0.001)
        XCTAssertEqual(metrics.workoutCount, 2)
        XCTAssertEqual(metrics.trainingDayCount, 2)
    }

    /// US-2 AC3.
    func testEmptyCacheYieldsEmptyState() async {
        cache.summaries = []

        let sut = makeSUT()
        await sut.load()

        XCTAssertEqual(sut.state, .empty)
    }

    /// An unreadable cache must not masquerade as "no training data".
    func testUnreadableCacheYieldsFailedState() async {
        cache.error = StubWorkoutCache.Failure()

        let sut = makeSUT()
        await sut.load()

        XCTAssertEqual(sut.state, .failed)
    }

    /// US-2 AC2: the dashboard always knows how fresh its data is.
    func testLoadPublishesLastSyncTimestamp() async throws {
        let syncedAt = reference.addingTimeInterval(-3600)
        await timestamps.setLastSync(syncedAt)

        let sut = makeSUT()
        await sut.load()

        let stored = try XCTUnwrap(sut.lastSync)
        XCTAssertEqual(stored.timeIntervalSince1970, syncedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testLastSyncIsNilWhenNoSyncEverCompleted() async {
        let sut = makeSUT()
        await sut.load()

        XCTAssertNil(sut.lastSync)
    }

    /// A refresh after a sync picks up the new cache content — and never
    /// falls back to `.loading`, so the dashboard does not flash a spinner.
    func testReloadPicksUpNewlyCachedWorkouts() async {
        cache.summaries = [summary(id: "w-1", daysAgo: 1, volume: 1000)]
        let sut = makeSUT()
        await sut.load()

        cache.summaries = [
            summary(id: "w-2", daysAgo: 0, volume: 200),
            summary(id: "w-1", daysAgo: 1, volume: 1000),
        ]
        await sut.load()

        guard case let .loaded(workouts, metrics) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(workouts.map(\.id), ["w-2", "w-1"])
        XCTAssertEqual(metrics.totalVolumeKg, 1200, accuracy: 0.001)
        XCTAssertEqual(cache.callCount, 2)
    }

    /// A slow read that a newer `load()` superseded must not publish its
    /// stale result on top of the fresher one (#27 adds pull-to-refresh on
    /// top of the initial `.task`).
    func testSupersededLoadDoesNotOverwriteTheNewerResult() async {
        cache.gatesFirstCall = true
        cache.results = [
            [summary(id: "stale", daysAgo: 30, volume: 100)],
            [summary(id: "fresh", daysAgo: 0, volume: 900)],
        ]
        let sut = makeSUT()

        let first = Task { await sut.load() }
        await cache.waitForFirstCall()
        await sut.load()
        cache.releaseFirstCall()
        await first.value

        guard case let .loaded(workouts, metrics) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(workouts.map(\.id), ["fresh"])
        XCTAssertEqual(metrics.totalVolumeKg, 900, accuracy: 0.001)
        XCTAssertEqual(cache.callCount, 2)
    }

    // MARK: - Sync (#28)

    func testSyncStatusStartsIdle() {
        XCTAssertEqual(makeSUT().syncStatus, .idle)
    }

    /// The whole point of `refresh()`: show the cache first, then go to Hevy.
    func testRefreshSyncsAndReadsTheCacheBack() async {
        // One entry per cache read: `refresh()` reads before the sync and
        // again after it, which is exactly what fills the window.
        cache.results = [[], [summary(id: "w-1", daysAgo: 2, volume: 800)]]

        let sut = makeSUT(withSyncer: true)
        await sut.refresh()

        let syncCount = await syncer.callCount
        XCTAssertEqual(syncCount, 1)
        XCTAssertEqual(cache.callCount, 2)
        guard case let .loaded(workouts, _) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(workouts.map(\.id), ["w-1"])
        XCTAssertEqual(sut.syncStatus, .idle)
    }

    /// #28 AC1: an unreachable API leaves the cached dashboard on screen.
    func testFailedSyncKeepsTheCachedDashboardAndRaisesTheBanner() async {
        cache.summaries = [summary(id: "cached", daysAgo: 3, volume: 700)]
        await syncer.setError(HevyServiceError.networkUnavailable)

        let sut = makeSUT(withSyncer: true)
        await sut.refresh()

        guard case let .loaded(workouts, metrics) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(workouts.map(\.id), ["cached"])
        XCTAssertEqual(metrics.totalVolumeKg, 700, accuracy: 0.001)
        XCTAssertEqual(sut.syncStatus, .failed(.offline))
    }

    /// A network failure and an HTTP failure must not collapse into one
    /// message — the issue asks for exactly this distinction.
    func testHTTPFailureIsReportedSeparatelyFromANetworkFailure() async {
        await syncer.setError(HevyServiceError.serviceUnavailable)

        let sut = makeSUT(withSyncer: true)
        await sut.refresh()

        XCTAssertEqual(sut.syncStatus, .failed(.serviceUnavailable))
    }

    /// #28 AC3.
    func testBannerDisappearsAfterASuccessfulSync() async {
        await syncer.setError(HevyServiceError.networkUnavailable)
        let sut = makeSUT(withSyncer: true)
        await sut.refresh()
        XCTAssertEqual(sut.syncStatus, .failed(.offline))

        await syncer.setError(nil)
        await sut.refresh()

        XCTAssertEqual(sut.syncStatus, .idle)
    }

    /// US-2 AC2: the timestamp survives a failed sync, so the user can tell
    /// how stale the cached window is.
    func testFailedSyncKeepsThePreviousTimestamp() async throws {
        let syncedAt = reference.addingTimeInterval(-7_200)
        await timestamps.setLastSync(syncedAt)
        await syncer.setError(HevyServiceError.networkUnavailable)

        let sut = makeSUT(withSyncer: true)
        await sut.refresh()

        let stored = try XCTUnwrap(sut.lastSync)
        XCTAssertEqual(stored.timeIntervalSince1970, syncedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    /// HTTP 401: `HevyService` has already wiped the key, so the dashboard
    /// hands over to onboarding instead of showing a banner.
    func testUnauthorizedRoutesToOnboardingWithoutABanner() async {
        await syncer.setError(HevyServiceError.unauthorized)
        let sut = makeSUT(withSyncer: true)
        var routed = false
        sut.onUnauthorized = { routed = true }

        await sut.refresh()

        XCTAssertTrue(routed)
        XCTAssertEqual(sut.syncStatus, .idle)
    }

    /// A cancelled request is not a connectivity problem and must not put an
    /// offline banner on a healthy dashboard.
    func testCancelledSyncReportsNoFailure() async {
        await syncer.setError(URLError(.cancelled))
        let sut = makeSUT(withSyncer: true)

        await sut.refresh()

        XCTAssertEqual(sut.syncStatus, .idle)
    }

    /// Repeated pull-to-refresh must not leave the older sync's outcome on
    /// screen after the newer one already answered.
    func testSupersededSyncDoesNotOverwriteTheNewerOutcome() async {
        await syncer.gateFirstCall()
        await syncer.setError(HevyServiceError.networkUnavailable)
        let sut = makeSUT(withSyncer: true)

        let first = Task { await sut.refresh() }
        await syncer.waitForFirstCall()
        await syncer.setError(nil)
        let second = Task { await sut.refresh() }
        await syncer.releaseFirstCall()
        await first.value
        await second.value

        XCTAssertEqual(sut.syncStatus, .idle)
        let syncCount = await syncer.callCount
        XCTAssertEqual(syncCount, 2)
    }

    /// Without a syncer — previews, and the cache-only tests above — `refresh()`
    /// is just a cache read and never claims a sync happened.
    func testRefreshWithoutASyncerIsAPlainCacheRead() async {
        cache.summaries = [summary(id: "w-1", daysAgo: 1, volume: 100)]

        let sut = makeSUT()
        await sut.refresh()

        XCTAssertEqual(cache.callCount, 1)
        XCTAssertEqual(sut.syncStatus, .idle)
    }

    // MARK: - Pull-to-refresh (#43, US-10)

    /// US-10 AC1: the pull goes all the way to Hevy and the timestamp the
    /// sync wrote is what the dashboard shows afterwards.
    func testRetrySyncsAndRenewsTheTimestamp() async throws {
        let previous = reference.addingTimeInterval(-7_200)
        let syncedAt = reference.addingTimeInterval(-30)
        await timestamps.setLastSync(previous)
        await syncer.setResult(SyncResult(workoutCount: 3, syncedAt: syncedAt, windowStart: reference))
        await syncer.recordSyncs(in: timestamps)
        cache.summaries = [summary(id: "w-1", daysAgo: 1, volume: 900)]

        let sut = makeSUT(withSyncer: true)
        await sut.retry()

        let syncCount = await syncer.callCount
        XCTAssertEqual(syncCount, 1)
        let stored = try XCTUnwrap(sut.lastSync)
        XCTAssertEqual(stored.timeIntervalSince1970, syncedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(sut.syncStatus, .idle)
    }

    /// US-10 AC2: the failure is announced, and the cached window it was
    /// supposed to replace stays exactly where it was.
    func testFailedRetryAnnouncesTheFailureAndKeepsTheCachedData() async throws {
        cache.summaries = [summary(id: "cached", daysAgo: 3, volume: 700)]
        await syncer.setError(HevyServiceError.networkUnavailable)

        let sut = makeSUT(withSyncer: true)
        await sut.retry()

        let notice = try XCTUnwrap(sut.refreshNotice)
        XCTAssertEqual(notice.failure, .offline)
        guard case let .loaded(workouts, _) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(workouts.map(\.id), ["cached"])
    }

    /// The case the AC is actually about: the banner already says "offline"
    /// and does not move when the same failure repeats, so the second pull
    /// needs a notice of its own or nothing on screen changes at all.
    func testASecondFailedRetryRaisesAFreshNotice() async throws {
        await syncer.setError(HevyServiceError.networkUnavailable)
        let sut = makeSUT(withSyncer: true)

        await sut.retry()
        let first = try XCTUnwrap(sut.refreshNotice)
        sut.dismissRefreshNotice()
        await sut.retry()
        let second = try XCTUnwrap(sut.refreshNotice)

        XCTAssertEqual(second.failure, first.failure)
        XCTAssertNotEqual(second.id, first.id)
    }

    /// The dashboard's own sync has the banner and nothing to confirm — a
    /// toast for a refresh nobody asked for would be noise on every tab
    /// switch and cold start.
    func testAutomaticRefreshRaisesNoNotice() async {
        await syncer.setError(HevyServiceError.networkUnavailable)
        let sut = makeSUT(withSyncer: true)

        await sut.reload()

        XCTAssertEqual(sut.syncStatus, .failed(.offline))
        XCTAssertNil(sut.refreshNotice)
    }

    /// A message about a failure that has since been made good would
    /// contradict the fresh timestamp printed above it.
    func testSuccessfulRetryClearsAStandingNotice() async {
        await syncer.setError(HevyServiceError.networkUnavailable)
        let sut = makeSUT(withSyncer: true)
        await sut.retry()
        XCTAssertNotNil(sut.refreshNotice)

        await syncer.setError(nil)
        await sut.retry()

        XCTAssertNil(sut.refreshNotice)
    }

    /// The next screen is onboarding, not the dashboard — a toast on the way
    /// out has nowhere to appear.
    func testUnauthorizedRetryRaisesNoNotice() async {
        await syncer.setError(HevyServiceError.unauthorized)
        let sut = makeSUT(withSyncer: true)
        sut.onUnauthorized = {}

        await sut.retry()

        XCTAssertNil(sut.refreshNotice)
    }

    /// A cancelled request says nothing about the refresh, so it gets no more
    /// of a toast than it gets a banner.
    func testCancelledRetryRaisesNoNotice() async {
        await syncer.setError(URLError(.cancelled))
        let sut = makeSUT(withSyncer: true)

        await sut.retry()

        XCTAssertNil(sut.refreshNotice)
    }

    func testDismissDropsTheNotice() async {
        await syncer.setError(HevyServiceError.networkUnavailable)
        let sut = makeSUT(withSyncer: true)
        await sut.retry()
        XCTAssertNotNil(sut.refreshNotice)

        sut.dismissRefreshNotice()

        XCTAssertNil(sut.refreshNotice)
    }

    /// SwiftUI cancels the `.refreshable` task when the view goes away — a
    /// tab switch while the pull is still running. That cancellation reaches
    /// the sync, and nothing newer is behind it to publish an outcome, so the
    /// sync itself has to clear `.syncing` before it gives up. Otherwise the
    /// strip claims "Syncing with Hevy…" for the rest of the app's life.
    func testRefreshCancelledFromOutsideDoesNotLeaveTheStripSyncing() async {
        await syncer.gateFirstCall()
        let sut = makeSUT(withSyncer: true)

        let pull = Task { await sut.retry() }
        await syncer.waitForFirstCall()
        XCTAssertEqual(sut.syncStatus, .syncing)

        pull.cancel()
        await syncer.releaseFirstCall()
        await pull.value

        // `.idle`, not merely "not syncing": a cancelled request says nothing
        // about connectivity, so publishing `.failed(.offline)` here would be
        // the very thing `performSync`'s `isCancellation` guard prevents.
        XCTAssertEqual(sut.syncStatus, .idle)
    }

    /// The same teardown, but the sync got through before it was cancelled.
    /// The workouts are in the cache by then, so the read that follows has to
    /// publish them — dropping it would leave the dashboard showing the old
    /// window under a stale timestamp until the user pulls a second time.
    func testSyncCancelledFromOutsideStillPublishesWhatItCached() async throws {
        let syncedAt = reference.addingTimeInterval(-30)
        cache.results = [
            [summary(id: "old", daysAgo: 5, volume: 400)],
            [summary(id: "fresh", daysAgo: 0, volume: 900)],
        ]
        await syncer.setResult(SyncResult(workoutCount: 1, syncedAt: syncedAt, windowStart: reference))
        await syncer.recordSyncs(in: timestamps)
        await syncer.gateFirstCall()
        let sut = makeSUT(withSyncer: true)

        let pull = Task { await sut.retry() }
        await syncer.waitForFirstCall()
        pull.cancel()
        await syncer.releaseFirstCall()
        await pull.value

        guard case let .loaded(workouts, _) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(workouts.map(\.id), ["fresh"])
        let stored = try XCTUnwrap(sut.lastSync)
        XCTAssertEqual(stored.timeIntervalSince1970, syncedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Reload after a discarded cache (#91)

    /// The window belongs to a Hevy key that was just replaced. Neither the
    /// previous account's workouts nor "No training data" is true while the
    /// re-sync runs, so the spinner stays up until the sync answered.
    func testReloadShowsNeitherTheStaleWindowNorTheEmptyStateWhileSyncing() async {
        cache.results = [[summary(id: "old-account", daysAgo: 2, volume: 500)], []]
        await syncer.gateFirstCall()
        let sut = makeSUT(withSyncer: true)
        await sut.load()
        guard case let .loaded(workouts, _) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(workouts.map(\.id), ["old-account"])

        let reload = Task { await sut.reload() }
        await syncer.waitForFirstCall()
        XCTAssertEqual(sut.state, .loading)

        await syncer.releaseFirstCall()
        await reload.value

        XCTAssertEqual(sut.state, .empty)
    }

    /// A sync that fails has no reload of its own — the held-back empty state
    /// must still reach the screen instead of leaving the spinner up forever.
    func testFailedSyncResolvesTheHeldSpinnerToTheEmptyState() async {
        await syncer.setError(HevyServiceError.networkUnavailable)
        let sut = makeSUT(withSyncer: true)

        await sut.reload()

        XCTAssertEqual(sut.state, .empty)
        XCTAssertEqual(sut.syncStatus, .failed(.offline))
    }

    /// Pull-to-refresh keeps its content: only a resting `.loading` holds the
    /// spinner back, a loaded dashboard reads through to the real answer.
    func testRefreshOnALoadedDashboardStillPublishesAnEmptyCache() async {
        cache.results = [[summary(id: "w-1", daysAgo: 1, volume: 900)], [], []]
        let sut = makeSUT(withSyncer: true)
        await sut.load()

        await sut.refresh()

        XCTAssertEqual(sut.state, .empty)
    }

    // MARK: - Helpers

    private func makeSUT(withSyncer: Bool = false) -> WorkoutListViewModel {
        WorkoutListViewModel(
            cache: cache,
            syncer: withSyncer ? syncer : nil,
            timestamps: timestamps,
            calendar: .current,
            now: { self.reference }
        )
    }

    private func summary(id: String, daysAgo: Int, volume: Double) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            title: "Session",
            startTime: reference.addingTimeInterval(Double(-daysAgo) * 86_400),
            volumeKg: volume,
            exerciseCount: 4,
            countedSetCount: 12
        )
    }
}
