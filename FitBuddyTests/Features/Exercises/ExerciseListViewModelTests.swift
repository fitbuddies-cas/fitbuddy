import XCTest
@testable import FitBuddy

/// Unit tests for `ExerciseListViewModel` (US-7 AC1, #37): the four states,
/// the realtime search and the difference between a window with no training
/// and a query that matches nothing.
@MainActor
final class ExerciseListViewModelTests: XCTestCase {
    private var cache: StubExerciseCache!

    /// Reference "now" for the window boundary.
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() async throws {
        try await super.setUp()
        cache = StubExerciseCache()
        await cache.setExercises(Self.catalogue)
    }

    override func tearDown() async throws {
        cache = nil
        try await super.tearDown()
    }

    private func makeSUT() -> ExerciseListViewModel {
        ExerciseListViewModel(cache: cache, now: { self.reference })
    }

    // MARK: - Loading

    func testStartsInLoading() {
        XCTAssertEqual(makeSUT().state, .loading)
    }

    func testLoadPublishesTheCachedExercises() async {
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.state, .loaded(Self.catalogue))
        XCTAssertEqual(sut.visibleExercises, Self.catalogue)
    }

    func testLoadReadsTheNinetyDayWindow() async {
        let sut = makeSUT()

        await sut.load()

        let requested = await cache.requestedDate
        XCTAssertEqual(requested, TrainingWindow.start(endingAt: reference))
    }

    func testAnEmptyWindowIsEmptyNotLoaded() async {
        await cache.setExercises([])
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.state, .empty)
        XCTAssertFalse(sut.hasNoSearchMatches)
    }

    func testAnUnreadableCacheIsAFailure() async {
        await cache.setError(StubExerciseCache.Failure())
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.state, .failed)
        XCTAssertTrue(sut.visibleExercises.isEmpty)
    }

    /// The failure card offers "Try again", so a second `load()` has to be
    /// able to succeed.
    func testRetryAfterAFailureLoadsTheExercises() async {
        await cache.setError(StubExerciseCache.Failure())
        let sut = makeSUT()
        await sut.load()
        XCTAssertEqual(sut.state, .failed)

        await cache.setError(nil)
        await sut.load()

        XCTAssertEqual(sut.state, .loaded(Self.catalogue))
    }

    // MARK: - Search (AC1)

    func testSearchFiltersByTitle() async {
        let sut = makeSUT()
        await sut.load()

        sut.searchText = "press"

        XCTAssertEqual(sut.visibleExercises.map(\.title), ["Bench Press (Barbell)", "Overhead Press (Barbell)"])
    }

    func testSearchIsCaseInsensitive() async {
        let sut = makeSUT()
        await sut.load()

        sut.searchText = "BeNcH"

        XCTAssertEqual(sut.visibleExercises.map(\.title), ["Bench Press (Barbell)"])
    }

    /// The list is a search over titles, not over muscle groups — that is the
    /// filter of AC2, which arrives with #38.
    func testSearchDoesNotMatchTheMuscleGroup() async {
        let sut = makeSUT()
        await sut.load()

        sut.searchText = "chest"

        XCTAssertTrue(sut.visibleExercises.isEmpty)
    }

    func testWhitespaceOnlyQueryShowsEverything() async {
        let sut = makeSUT()
        await sut.load()

        sut.searchText = "   "

        XCTAssertEqual(sut.visibleExercises, Self.catalogue)
        XCTAssertFalse(sut.hasNoSearchMatches)
    }

    /// The «No exercises found» case: a statement about the query, not about
    /// the window behind it.
    func testAQueryThatMatchesNothingIsNoMatchesNotEmpty() async {
        let sut = makeSUT()
        await sut.load()

        sut.searchText = "kettlebell"

        XCTAssertTrue(sut.visibleExercises.isEmpty)
        XCTAssertTrue(sut.hasNoSearchMatches)
        XCTAssertEqual(sut.state, .loaded(Self.catalogue))
    }

    /// Clearing the field puts the full list back — the filter never mutates
    /// what was loaded.
    func testClearingTheSearchRestoresTheFullList() async {
        let sut = makeSUT()
        await sut.load()
        sut.searchText = "squat"

        sut.searchText = ""

        XCTAssertEqual(sut.visibleExercises, Self.catalogue)
    }

    /// A query typed before the read returned must not claim "not found" over
    /// a list that is still loading.
    func testNoMatchesStaysFalseWhileLoading() {
        let sut = makeSUT()

        sut.searchText = "bench"

        XCTAssertFalse(sut.hasNoSearchMatches)
    }

    // MARK: - Fixtures

    private static let catalogue: [ExerciseSummary] = [
        make(id: "1", title: "Bench Press (Barbell)", group: .chest),
        make(id: "2", title: "Squat (Barbell)", group: .legs),
        make(id: "3", title: "Overhead Press (Barbell)", group: .shoulders),
    ]

    private static func make(id: String, title: String, group: MuscleGroup) -> ExerciseSummary {
        ExerciseSummary(
            id: id,
            title: title,
            muscleGroup: group,
            sessionCount: 4,
            countedSetCount: 12,
            volumeKg: 8_000,
            lastPerformed: Date(timeIntervalSince1970: 1_749_000_000)
        )
    }
}
