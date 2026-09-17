import XCTest
@testable import FitBuddy

/// Unit tests for the profile screen in Settings (US-13 AC5, #191).
@MainActor
final class TrainingProfileSettingsViewModelTests: XCTestCase {
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

    func testLoadShowsTheStoredProfile() async {
        await store.save(TrainingProfile(goal: .loseFat, experience: .overThreeYears))

        let sut = makeSUT()
        await sut.load()

        XCTAssertEqual(sut.goal, .loseFat)
        XCTAssertEqual(sut.experience, .overThreeYears)
        XCTAssertTrue(sut.hasProfile)
    }

    /// Unlike onboarding, a change is written as it is made — a settings
    /// screen with a separate save step is one the user leaves without it.
    func testSelectingWritesImmediately() async {
        let sut = makeSUT()
        await sut.load()

        await sut.select(goal: .improveEndurance)

        let stored = await store.profile
        XCTAssertEqual(stored.goal, .improveEndurance)
    }

    func testSelectingTheSelectedAnswerClearsIt() async {
        await store.save(TrainingProfile(goal: .buildMuscle, experience: .underOneYear))
        let sut = makeSUT()
        await sut.load()

        await sut.select(goal: .buildMuscle)

        XCTAssertNil(sut.goal)
        let stored = await store.profile
        XCTAssertNil(stored.goal)
        XCTAssertEqual(stored.experience, .underOneYear)
    }

    /// Removing is a decision, not a blank slate: the app must behave as it
    /// does without a profile, and must not ask again on the next launch.
    func testRemovingClearsAndSettlesTheStep() async {
        await store.save(TrainingProfile(goal: .getStronger))
        let sut = makeSUT()
        await sut.load()

        await sut.remove()

        XCTAssertFalse(sut.hasProfile)
        let stored = await store.profile
        XCTAssertTrue(stored.isEmpty)
        let decided = await store.isDecided
        XCTAssertTrue(decided)
    }

    /// Clearing the last answer one tap at a time ends in the same place as
    /// "Remove profile" — otherwise the two ways to an empty profile would
    /// leave the step in two different states.
    func testClearingTheLastAnswerSettlesTheStepToo() async {
        await store.save(TrainingProfile(goal: .stayFit))
        let sut = makeSUT()
        await sut.load()

        await sut.select(goal: .stayFit)

        let decided = await store.isDecided
        XCTAssertTrue(decided)
    }

    private func makeSUT() -> TrainingProfileSettingsViewModel {
        TrainingProfileSettingsViewModel(store: store)
    }
}
