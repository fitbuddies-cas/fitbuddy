import XCTest
@testable import FitBuddy

/// Unit tests for `ExerciseListViewModel` (US-7, #37/#38): the four states, the
/// realtime search, the muscle-group filter and the way the two combine, and
/// the difference between a window with no training and a filter that matches
/// nothing.
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
        XCTAssertFalse(sut.hasNoMatches)
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
    /// The list is a tab root (#264): its `.task` re-runs on every return to
    /// the tab. The rows must stay on screen while the fresh read is under
    /// way, or every tab switch would flash a spinner and drop the search.
    func testReloadingOverALoadedWindowKeepsTheRowsUntilTheFreshReadLands() async {
        let sut = makeSUT()
        await sut.load()
        let updated = Array(Self.catalogue.dropFirst())
        await cache.setExercises(updated)
        await cache.setHoldsReads(true)

        let reload = Task { await sut.load() }
        await awaitHeldRead()

        XCTAssertEqual(sut.state, .loaded(Self.catalogue), "Still the old rows while the read is pending")
        await cache.releaseReads()
        await reload.value
        XCTAssertEqual(sut.state, .loaded(updated))
    }

    /// The other half of the rule above: a retry from the failure card is
    /// visible as a retry.
    func testRetryAfterAFailureShowsTheSpinnerWhileReading() async {
        await cache.setError(StubExerciseCache.Failure())
        let sut = makeSUT()
        await sut.load()
        XCTAssertEqual(sut.state, .failed)
        await cache.setError(nil)
        await cache.setHoldsReads(true)

        let retry = Task { await sut.load() }
        await awaitHeldRead()

        XCTAssertEqual(sut.state, .loading)
        await cache.releaseReads()
        await retry.value
        XCTAssertEqual(sut.state, .loaded(Self.catalogue))
    }

    /// Blocks until the view model's read has reached the held cache.
    private func awaitHeldRead() async {
        while await cache.heldReadCount == 0 {
            await Task.yield()
        }
    }

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

    /// The text search runs over titles, not over muscle groups — the group is
    /// the job of the chip filter (AC2), not the search field.
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
        XCTAssertFalse(sut.hasNoMatches)
    }

    /// The «No exercises found» case: a statement about the query, not about
    /// the window behind it.
    func testAQueryThatMatchesNothingIsNoMatchesNotEmpty() async {
        let sut = makeSUT()
        await sut.load()

        sut.searchText = "kettlebell"

        XCTAssertTrue(sut.visibleExercises.isEmpty)
        XCTAssertTrue(sut.hasNoMatches)
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

        XCTAssertFalse(sut.hasNoMatches)
    }

    // MARK: - Muscle-group filter (AC2)

    /// Every group the app classifies into is offered as a chip, in the
    /// canonical order (AC1).
    func testFilterGroupsCoverEveryMuscleGroup() {
        XCTAssertEqual(makeSUT().filterGroups, MuscleGroup.allCases)
    }

    func testNoGroupSelectedShowsEverything() async {
        let sut = makeSUT()
        await sut.load()

        XCTAssertTrue(sut.selectedMuscleGroups.isEmpty)
        XCTAssertEqual(sut.visibleExercises, Self.catalogue)
        XCTAssertFalse(sut.isFiltering)
    }

    func testSelectingAGroupNarrowsToThatGroup() async {
        let sut = makeSUT()
        await sut.load()

        sut.toggle(.legs)

        XCTAssertEqual(sut.visibleExercises.map(\.title), ["Squat (Barbell)"])
        XCTAssertTrue(sut.isFiltering)
    }

    /// AC2: several groups combine with OR — a movement shows if it belongs to
    /// any selected group.
    func testMultipleGroupsUseOrLogic() async {
        let sut = makeSUT()
        await sut.load()

        sut.toggle(.legs)
        sut.toggle(.shoulders)

        XCTAssertEqual(
            sut.visibleExercises.map(\.title),
            ["Squat (Barbell)", "Overhead Press (Barbell)"]
        )
    }

    func testTogglingAGroupOffRestoresIt() async {
        let sut = makeSUT()
        await sut.load()
        sut.toggle(.legs)

        sut.toggle(.legs)

        XCTAssertTrue(sut.selectedMuscleGroups.isEmpty)
        XCTAssertEqual(sut.visibleExercises, Self.catalogue)
    }

    /// A chip whose group has no movement in the window is the «no matches»
    /// case, not an empty window.
    func testAGroupWithNoExercisesIsNoMatchesNotEmpty() async {
        let sut = makeSUT()
        await sut.load()

        sut.toggle(.core)

        XCTAssertTrue(sut.visibleExercises.isEmpty)
        XCTAssertTrue(sut.hasNoMatches)
        XCTAssertEqual(sut.state, .loaded(Self.catalogue))
    }

    // MARK: - Search + filter combined (AC3)

    func testMuscleFilterAndSearchCombine() async {
        let sut = makeSUT()
        await sut.load()

        sut.toggle(.chest)
        sut.toggle(.shoulders)
        sut.searchText = "press"

        XCTAssertEqual(
            sut.visibleExercises.map(\.title),
            ["Bench Press (Barbell)", "Overhead Press (Barbell)"]
        )
    }

    func testSearchInsideAGroupCanMatchNothing() async {
        let sut = makeSUT()
        await sut.load()

        sut.toggle(.legs)
        sut.searchText = "bench"

        XCTAssertTrue(sut.visibleExercises.isEmpty)
        XCTAssertTrue(sut.hasNoMatches)
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
