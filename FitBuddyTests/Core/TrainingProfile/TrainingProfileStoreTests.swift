import XCTest
@testable import FitBuddy

/// Unit tests for the training profile store (US-13, #190).
final class TrainingProfileStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: TrainingProfileStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = TrainingProfileStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        try await super.tearDown()
    }

    // MARK: - Round trip

    func testStartsEmpty() async {
        let profile = await sut.profile
        XCTAssertTrue(profile.isEmpty)
        let decided = await sut.isDecided
        XCTAssertFalse(decided)
    }

    func testSavesAndReadsBackBothAnswers() async {
        await sut.save(TrainingProfile(goal: .improveEndurance, experience: .oneToThreeYears))

        let profile = await sut.profile
        XCTAssertEqual(profile.goal, .improveEndurance)
        XCTAssertEqual(profile.experience, .oneToThreeYears)
    }

    /// Half an answer is a valid profile — the questions are independent.
    func testAHalfProfileSurvives() async {
        await sut.save(TrainingProfile(goal: .buildMuscle))

        let profile = await sut.profile
        XCTAssertEqual(profile.goal, .buildMuscle)
        XCTAssertNil(profile.experience)
        XCTAssertFalse(profile.isEmpty)
    }

    /// Clearing one answer in Settings has to remove it, not leave the old
    /// value behind where the prompt would keep reading it (#191).
    func testClearingOneAnswerRemovesIt() async {
        await sut.save(TrainingProfile(goal: .getStronger, experience: .overThreeYears))

        await sut.save(TrainingProfile(goal: nil, experience: .overThreeYears))

        let profile = await sut.profile
        XCTAssertNil(profile.goal)
        XCTAssertEqual(profile.experience, .overThreeYears)
    }

    /// The raw values are on disk. Renaming a case must not orphan a stored
    /// profile, which is why they are spelled out rather than derived.
    func testStoredValuesAreTheRawValues() async {
        await sut.save(TrainingProfile(goal: .loseFat, experience: .underOneYear))

        XCTAssertEqual(defaults.string(forKey: TrainingProfileStore.goalKey), "lose_fat")
        XCTAssertEqual(defaults.string(forKey: TrainingProfileStore.experienceKey), "under_1y")
    }

    /// A value the app no longer knows — an older build's case, a hand-edited
    /// domain — reads as no answer rather than crashing.
    func testAnUnknownStoredValueReadsAsNoAnswer() async {
        defaults.set("cycling_everest", forKey: TrainingProfileStore.goalKey)

        let profile = await sut.profile
        XCTAssertNil(profile.goal)
    }

    // MARK: - Decisions

    func testAnsweringCountsAsDecided() async {
        await sut.save(TrainingProfile(goal: .stayFit))

        let decided = await sut.isDecided
        XCTAssertTrue(decided)
    }

    func testSkippingCountsAsDecided() async {
        await sut.setSkipped()

        let decided = await sut.isDecided
        XCTAssertTrue(decided)
        let profile = await sut.profile
        XCTAssertTrue(profile.isEmpty)
    }

    /// Removing the answers is not the same as asking again: a user who
    /// cleared their profile in Settings has still settled the step.
    func testClearingTheProfileLeavesTheSkipDecision() async {
        await sut.setSkipped()
        await sut.save(TrainingProfile(goal: .buildMuscle))

        await sut.clearProfile()

        let skipped = await sut.isSkipped
        XCTAssertTrue(skipped)
    }

    // MARK: - Reset

    /// "Delete all data" asks again — but must not make the install look like
    /// one that predates the step, or it would never ask at all.
    func testClearDropsTheDecisionAndKeepsTheIntroductionMarker() async {
        await sut.markIntroductionSeen()
        await sut.setSkipped()
        await sut.save(TrainingProfile(goal: .getStronger))

        await sut.clear()

        let decided = await sut.isDecided
        XCTAssertFalse(decided)
        let seen = await sut.hasSeenIntroduction
        XCTAssertTrue(seen)
    }
}
