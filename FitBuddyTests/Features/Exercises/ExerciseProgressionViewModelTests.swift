import XCTest
@testable import FitBuddy

/// Unit tests for `ExerciseProgressionViewModel` (US-9, #42): which of the
/// screen's states a given window produces.
@MainActor
final class ExerciseProgressionViewModelTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)
    private var cache: StubProgressionCache!

    override func setUp() async throws {
        try await super.setUp()
        cache = StubProgressionCache()
    }

    override func tearDown() async throws {
        cache = nil
        try await super.tearDown()
    }

    func testStartsLoading() {
        XCTAssertEqual(makeSUT().state, .loading)
    }

    /// The row's title and muscle group are on screen before the read lands —
    /// the tapped row already knew them.
    func testCarriesTheTappedRowFromTheStart() {
        let sut = makeSUT()

        XCTAssertEqual(sut.exercise.title, "Bench Press (Barbell)")
        XCTAssertEqual(sut.exercise.muscleGroup, .chest)
    }

    /// AC1: two sessions or more produce a curve.
    func testTwoSessionsLoadTheCurve() async {
        cache.progression = progression([100, 104])

        let sut = makeSUT()
        await sut.load()

        guard case .loaded(let loaded) = sut.state else {
            return XCTFail("Expected .loaded, got \(sut.state)")
        }
        XCTAssertEqual(loaded.points.count, 2)
    }

    /// AC3: one usable session is not a curve.
    func testOneSessionYieldsInsufficientData() async {
        cache.progression = progression([100])

        let sut = makeSUT()
        await sut.load()

        guard case .insufficientData = sut.state else {
            return XCTFail("Expected .insufficientData, got \(sut.state)")
        }
        XCTAssertEqual(sut.plottedSessionCount, 1)
    }

    /// A movement trained only without weight has no point at all — still the
    /// AC3 case, and the hint says zero rather than one.
    func testAMovementWithoutUsableSetsYieldsInsufficientData() async {
        cache.progression = progression([])

        let sut = makeSUT()
        await sut.load()

        guard case .insufficientData = sut.state else {
            return XCTFail("Expected .insufficientData, got \(sut.state)")
        }
        XCTAssertEqual(sut.plottedSessionCount, 0)
    }

    /// The cache was replaced under the open screen (#91): the movement is
    /// gone from the window, which is not the same as having too little data.
    func testAMissingMovementIsUnavailable() async {
        cache.progression = nil

        let sut = makeSUT()
        await sut.load()

        XCTAssertEqual(sut.state, .unavailable)
    }

    func testAnUnreadableCacheFails() async {
        cache.error = StubProgressionCache.Failure()

        let sut = makeSUT()
        await sut.load()

        XCTAssertEqual(sut.state, .failed)
    }

    // MARK: - Plateau badge (AC2)

    func testPlateauedCurveShowsTheBadge() async {
        cache.progression = progression([100, 98, 99, 97])

        let sut = makeSUT()
        await sut.load()

        XCTAssertTrue(sut.showsPlateauBadge)
    }

    func testProgressingCurveShowsNoBadge() async {
        cache.progression = progression([100, 98, 99, 105])

        let sut = makeSUT()
        await sut.load()

        XCTAssertFalse(sut.showsPlateauBadge)
    }

    /// A single session cannot have stalled, and a badge over it would be a
    /// verdict the data does not support.
    func testTooLittleDataNeverShowsTheBadge() async {
        cache.progression = progression([100])

        let sut = makeSUT()
        await sut.load()

        XCTAssertFalse(sut.showsPlateauBadge)
    }

    // MARK: - The "not enough data" sentence

    /// Singular, plural and none — a count folded into prose is a decision
    /// with a right answer, so it gets held in place here.
    func testTheSentenceCountsWhatTheWindowHolds() async {
        cache.progression = progression([])
        let none = makeSUT()
        await none.load()
        XCTAssertTrue(none.sessionsSoFarDescription.contains("no set"))

        cache.progression = progression([100])
        let one = makeSUT()
        await one.load()
        XCTAssertTrue(one.sessionsSoFarDescription.contains("one session"))

        cache.progression = progression([100, 102, 104])
        let several = makeSUT()
        await several.load()
        XCTAssertTrue(several.sessionsSoFarDescription.contains("3 sessions"))
    }

    /// The window length comes from `TrainingWindow`, not from the copy — the
    /// two drifting apart is what the view model's own comment argues against.
    func testTheSentenceNamesTheRealWindowLength() async {
        cache.progression = progression([100])

        let sut = makeSUT()
        await sut.load()

        XCTAssertTrue(sut.sessionsSoFarDescription.contains("\(TrainingWindow.days) days"))
    }

    // MARK: - Window

    /// The same 90-day window every other screen reads.
    func testReadsTheNinetyDayWindowForTheTappedMovement() async {
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(cache.requestedID, "bench")
        XCTAssertEqual(cache.requestedSince, TrainingWindow.start(endingAt: reference))
    }

    // MARK: - Helpers

    private func makeSUT() -> ExerciseProgressionViewModel {
        ExerciseProgressionViewModel(
            cache: cache,
            exercise: ExerciseIdentity(
                id: "bench",
                title: "Bench Press (Barbell)",
                muscleGroup: .chest
            ),
            now: { self.reference }
        )
    }

    private func progression(_ estimates: [Double]) -> ExerciseProgression {
        ExerciseProgression(
            id: "bench",
            title: "Bench Press (Barbell)",
            points: estimates.enumerated().map { offset, estimate in
                ProgressionPoint(
                    sessionStart: reference.addingTimeInterval(Double(offset) * 86_400),
                    estimatedOneRepMaxKg: estimate,
                    weightKg: estimate * 0.8,
                    reps: 8
                )
            }
        )
    }
}
