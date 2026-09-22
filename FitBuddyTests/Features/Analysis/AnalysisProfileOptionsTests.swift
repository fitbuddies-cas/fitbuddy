import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisProfileOptions` (US-15 AC1, #185): which profiles
/// the intro screen offers, and which one it starts on.
final class AnalysisProfileOptionsTests: XCTestCase {
    // MARK: - What is offered

    /// AC1, first row: a Hevy-only install has one kind of training, so there
    /// is nothing to choose between and "Strength" is implicit.
    func testAStrengthOnlyWindowOffersNoChoice() {
        let options = AnalysisProfileOptions(domainCounts: [.strength: 14])
        XCTAssertEqual(options.available, [.strength])
        XCTAssertEqual(options.preselected, .strength)
        XCTAssertFalse(options.isChoice)
    }

    func testAnEnduranceOnlyWindowOffersNoChoiceEither() {
        let options = AnalysisProfileOptions(domainCounts: [.endurance: 9])
        XCTAssertEqual(options.available, [.endurance])
        XCTAssertEqual(options.preselected, .endurance)
        XCTAssertFalse(options.isChoice)
    }

    /// AC1, second row: lifts and runs in the same window — three options,
    /// "Overall load" preselected.
    func testAMixedWindowOffersAllThreeWithOverallLoadPreselected() {
        let options = AnalysisProfileOptions(domainCounts: [.strength: 14, .endurance: 9])
        XCTAssertEqual(options.available, [.strength, .endurance, .overallLoad])
        XCTAssertEqual(options.preselected, .overallLoad)
        XCTAssertTrue(options.isChoice)
    }

    /// A single run is enough to make the window a mixed one. It is also
    /// enough to make "Overall load" warn about thin endurance data — which is
    /// exactly why the choice exists: the user can answer that by picking
    /// "Strength" (US-15 AC4).
    func testASingleEnduranceSessionOpensTheChoice() {
        let options = AnalysisProfileOptions(domainCounts: [.strength: 14, .endurance: 1])
        XCTAssertEqual(options.available, [.strength, .endurance, .overallLoad])
        XCTAssertEqual(options.preselected, .overallLoad)
    }

    /// An empty cache still analyses strength, it just has nothing to analyse
    /// yet — the run reports "no training data", and the picker does not
    /// promise a choice on the way there.
    func testAnEmptyWindowFallsBackToStrengthAlone() {
        let options = AnalysisProfileOptions(domainCounts: [:])
        XCTAssertEqual(options.available, [.strength])
        XCTAssertEqual(options.preselected, .strength)
        XCTAssertFalse(options.isChoice)
    }

    func testADomainCountedAtZeroIsNotOffered() {
        let options = AnalysisProfileOptions(domainCounts: [.strength: 14, .endurance: 0])
        XCTAssertEqual(options.available, [.strength])
        XCTAssertEqual(options.preselected, .strength)
    }

    /// The order is `AnalysisProfile.allCases`, not the dictionary's: a
    /// segmented control whose segments swap places between two visits reads
    /// as if the app had changed its mind.
    func testTheOrderIsFixed() {
        let first = AnalysisProfileOptions(domainCounts: [.endurance: 9, .strength: 14])
        let second = AnalysisProfileOptions(domainCounts: [.strength: 14, .endurance: 9])
        XCTAssertEqual(first.available, second.available)
        XCTAssertEqual(first.available, [.strength, .endurance, .overallLoad])
    }

    // MARK: - What is remembered

    func testTheRememberedProfileWinsOverTheDefault() {
        let options = AnalysisProfileOptions(
            domainCounts: [.strength: 14, .endurance: 9],
            remembered: .strength
        )
        XCTAssertEqual(options.preselected, .strength)
        XCTAssertEqual(options.available, [.strength, .endurance, .overallLoad])
    }

    /// The user connected Strava last week, chose "Endurance", and has since
    /// removed it: the remembered choice has no data behind it any more, so
    /// the default takes over rather than preselecting an empty analysis.
    func testARememberedProfileWithoutDataFallsBackToTheDefault() {
        let options = AnalysisProfileOptions(
            domainCounts: [.strength: 14],
            remembered: .endurance
        )
        XCTAssertEqual(options.available, [.strength])
        XCTAssertEqual(options.preselected, .strength)
    }

    func testNoRememberedProfileLeavesTheDefaultInPlace() {
        XCTAssertEqual(
            AnalysisProfileOptions(domainCounts: [.strength: 3, .endurance: 4]).preselected,
            .overallLoad
        )
    }
}
