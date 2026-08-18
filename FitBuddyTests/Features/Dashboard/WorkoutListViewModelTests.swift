import XCTest
@testable import FitBuddy

/// Unit tests for `WorkoutListViewModel` (issue #26): cache-only reads, the
/// 90-day window and the metrics it exposes to the dashboard.
@MainActor
final class WorkoutListViewModelTests: XCTestCase {
    private var cache: StubWorkoutCache!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var timestamps: SyncTimestampStore!

    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() async throws {
        try await super.setUp()
        cache = StubWorkoutCache()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        timestamps = SyncTimestampStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        cache = nil
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

    // MARK: - Helpers

    private func makeSUT() -> WorkoutListViewModel {
        WorkoutListViewModel(
            cache: cache,
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
