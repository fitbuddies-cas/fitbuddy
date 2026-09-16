import XCTest
@testable import FitBuddy

/// Unit tests for the training profile screen's view model (US-13, #190).
@MainActor
final class TrainingProfileViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: TrainingProfileStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = TrainingProfileStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        try await super.tearDown()
    }

    func testStartsUnknownUntilBootstrapped() {
        XCTAssertEqual(makeSUT().state, .unknown)
    }

    func testAnEmptyStoreLandsOnIdle() async {
        let sut = makeSUT()

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertNil(sut.goal)
        XCTAssertNil(sut.experience)
    }

    /// Returning to the step mid-onboarding shows the previous answers rather
    /// than a blank screen.
    func testBootstrapRestoresStoredAnswers() async {
        await store.save(TrainingProfile(goal: .improveEndurance, experience: .underOneYear))

        let sut = makeSUT()
        await sut.bootstrap()

        XCTAssertEqual(sut.goal, .improveEndurance)
        XCTAssertEqual(sut.experience, .underOneYear)
        XCTAssertEqual(sut.state, .saved)
    }

    func testBootstrapRestoresASkippedDecision() async {
        await store.setSkipped()

        let sut = makeSUT()
        await sut.bootstrap()

        XCTAssertEqual(sut.state, .skipped)
    }

    // MARK: - Saving

    /// Nothing is written while the user is still choosing: backing out of the
    /// screen must not leave half a profile behind.
    func testSelectingAloneWritesNothing() async {
        let sut = makeSUT()
        await sut.bootstrap()

        sut.goal = .buildMuscle

        let stored = await store.profile
        XCTAssertTrue(stored.isEmpty)
    }

    func testSavingWritesAndFinishes() async {
        var finished = false
        let sut = makeSUT()
        sut.onFinished = { finished = true }
        await sut.bootstrap()
        sut.goal = .getStronger
        sut.experience = .oneToThreeYears

        await sut.save()

        let stored = await store.profile
        XCTAssertEqual(stored.goal, .getStronger)
        XCTAssertEqual(stored.experience, .oneToThreeYears)
        XCTAssertEqual(sut.state, .saved)
        XCTAssertTrue(finished)
    }

    /// One answer is enough — the questions are independent.
    func testOneAnswerIsSavable() async {
        let sut = makeSUT()
        await sut.bootstrap()
        sut.experience = .overThreeYears

        XCTAssertTrue(sut.canSave)
        await sut.save()

        let stored = await store.profile
        XCTAssertEqual(stored.experience, .overThreeYears)
        XCTAssertNil(stored.goal)
    }

    /// With neither answered there is nothing to save, and "Skip for now" is
    /// the honest way out.
    func testNothingAnsweredCannotBeSaved() async {
        let sut = makeSUT()
        await sut.bootstrap()

        XCTAssertFalse(sut.canSave)
        await sut.save()

        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Skipping

    func testSkippingRecordsTheDecisionAndFinishes() async {
        var finished = false
        let sut = makeSUT()
        sut.onFinished = { finished = true }
        await sut.bootstrap()

        await sut.skip()

        let skipped = await store.isSkipped
        XCTAssertTrue(skipped)
        XCTAssertEqual(sut.state, .skipped)
        XCTAssertTrue(finished)
    }

    /// A reset restarts onboarding; the fields must not still hold the
    /// previous session's answers.
    func testResetClearsTheFields() async {
        await store.save(TrainingProfile(goal: .loseFat))
        let sut = makeSUT()
        await sut.bootstrap()

        sut.reset()

        XCTAssertNil(sut.goal)
        XCTAssertEqual(sut.state, .unknown)
    }

    private func makeSUT() -> TrainingProfileViewModel {
        TrainingProfileViewModel(store: store)
    }
}
