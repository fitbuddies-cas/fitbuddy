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
        cache.summaries = []
        syncer.onSync = { [self] in
            cache.summaries = [summary(id: "w-1", daysAgo: 2, volume: 800)]
        }

        let sut = makeSUT(withSyncer: true)
        await sut.refresh()

        XCTAssertEqual(syncer.callCount, 1)
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
        syncer.error = HevyServiceError.networkUnavailable

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
        syncer.error = HevyServiceError.serviceUnavailable

        let sut = makeSUT(withSyncer: true)
        await sut.refresh()

        XCTAssertEqual(sut.syncStatus, .failed(.serviceUnavailable))
    }

    /// #28 AC3.
    func testBannerDisappearsAfterASuccessfulSync() async {
        syncer.error = HevyServiceError.networkUnavailable
        let sut = makeSUT(withSyncer: true)
        await sut.refresh()
        XCTAssertEqual(sut.syncStatus, .failed(.offline))

        syncer.error = nil
        await sut.refresh()

        XCTAssertEqual(sut.syncStatus, .idle)
    }

    /// US-2 AC2: the timestamp survives a failed sync, so the user can tell
    /// how stale the cached window is.
    func testFailedSyncKeepsThePreviousTimestamp() async throws {
        let syncedAt = reference.addingTimeInterval(-7_200)
        await timestamps.setLastSync(syncedAt)
        syncer.error = HevyServiceError.networkUnavailable

        let sut = makeSUT(withSyncer: true)
        await sut.refresh()

        let stored = try XCTUnwrap(sut.lastSync)
        XCTAssertEqual(stored.timeIntervalSince1970, syncedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    /// HTTP 401: `HevyService` has already wiped the key, so the dashboard
    /// hands over to onboarding instead of showing a banner.
    func testUnauthorizedRoutesToOnboardingWithoutABanner() async {
        syncer.error = HevyServiceError.unauthorized
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
        syncer.error = URLError(.cancelled)
        let sut = makeSUT(withSyncer: true)

        await sut.refresh()

        XCTAssertEqual(sut.syncStatus, .idle)
    }

    /// Repeated pull-to-refresh must not leave the older sync's outcome on
    /// screen after the newer one already answered.
    func testSupersededSyncDoesNotOverwriteTheNewerOutcome() async {
        syncer.gatesFirstCall = true
        syncer.error = HevyServiceError.networkUnavailable
        let sut = makeSUT(withSyncer: true)

        let first = Task { await sut.refresh() }
        await syncer.waitForFirstCall()
        syncer.error = nil
        let second = Task { await sut.refresh() }
        syncer.releaseFirstCall()
        await first.value
        await second.value

        XCTAssertEqual(sut.syncStatus, .idle)
        XCTAssertEqual(syncer.callCount, 2)
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
