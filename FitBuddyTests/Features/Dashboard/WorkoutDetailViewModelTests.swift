import XCTest
@testable import FitBuddy

/// Unit tests for `WorkoutDetailViewModel` (#98): the four states, and the
/// distinction between a session that is gone and a cache that cannot be read.
@MainActor
final class WorkoutDetailViewModelTests: XCTestCase {
    private var cache: StubWorkoutDetailCache!

    override func setUp() async throws {
        try await super.setUp()
        cache = StubWorkoutDetailCache()
        cache.details = [Self.session]
    }

    override func tearDown() async throws {
        cache = nil
        try await super.tearDown()
    }

    private func makeSUT(workoutID: String = "w-1") -> WorkoutDetailViewModel {
        WorkoutDetailViewModel(cache: cache, workoutID: workoutID)
    }

    // MARK: - Loading

    func testStartsInLoading() {
        XCTAssertEqual(makeSUT().state, .loading)
    }

    func testLoadPublishesTheCachedSession() async {
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.state, .loaded(Self.session))
        XCTAssertEqual(cache.requestedID, "w-1")
    }

    func testStaysLoadingUntilTheReadReturns() async {
        cache.gatesCalls = true
        let sut = makeSUT()

        let load = Task { await sut.load() }
        await cache.waitForCall()
        XCTAssertEqual(sut.state, .loading)

        cache.release()
        await load.value
        XCTAssertEqual(sut.state, .loaded(Self.session))
    }

    // MARK: - Missing vs. failed

    /// A sync replaced the window while the screen was open: the session is
    /// gone, and that is a statement about the data, not about the store.
    func testAWorkoutTheCacheNoLongerHoldsIsMissing() async {
        let sut = makeSUT(workoutID: "gone")

        await sut.load()

        XCTAssertEqual(sut.state, .missing)
    }

    func testAnUnreadableCacheIsAFailure() async {
        cache.error = StubWorkoutDetailCache.Failure()
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.state, .failed)
    }

    /// The failure state offers "Try again", so a second `load()` has to be
    /// able to succeed.
    func testRetryAfterAFailureLoadsTheSession() async {
        cache.error = StubWorkoutDetailCache.Failure()
        let sut = makeSUT()
        await sut.load()
        XCTAssertEqual(sut.state, .failed)

        cache.error = nil
        await sut.load()

        XCTAssertEqual(sut.state, .loaded(Self.session))
        XCTAssertEqual(cache.callCount, 2)
    }

    // MARK: - Cancellation

    /// Navigating back cancels the screen's `.task`. A cancelled read says
    /// nothing about the cache, so it must not leave `.failed` behind.
    func testACancelledReadPublishesNothing() async {
        cache.gatesCalls = true
        cache.error = StubWorkoutDetailCache.Failure()
        let sut = makeSUT()

        let load = Task { await sut.load() }
        await cache.waitForCall()
        load.cancel()
        cache.release()
        await load.value

        XCTAssertEqual(sut.state, .loading)
    }

    // MARK: - Fixture

    private static let exercise = ExerciseDetail(
        index: 0,
        title: "Bench Press (Barbell)",
        sets: [
            SetDetail(index: 0, type: .warmup, weightKg: 60, reps: 10,
                      distanceMeters: nil, durationSeconds: nil, rpe: nil),
            SetDetail(index: 1, type: .normal, weightKg: 100, reps: 8,
                      distanceMeters: nil, durationSeconds: nil, rpe: 9.5),
        ]
    )

    private static let session = WorkoutDetail(
        id: "w-1",
        title: "Push Day",
        workoutDescription: "Felt strong",
        startTime: Date(timeIntervalSince1970: 1_750_000_000),
        endTime: Date(timeIntervalSince1970: 1_750_003_600),
        volumeKg: exercise.volumeKg,
        countedSetCount: exercise.countedSetCount,
        exercises: [exercise]
    )
}
