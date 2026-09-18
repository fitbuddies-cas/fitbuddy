import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisProfile` (US-15 AC1, #185): what each profile
/// covers, and what happens to a profile whose half of the window is empty.
final class AnalysisProfileTests: XCTestCase {
    private static let reference = Date(timeIntervalSince1970: 1_788_000_000)

    // MARK: - Coverage

    func testEachProfileCoversTheDomainsItsNameNames() {
        XCTAssertEqual(AnalysisProfile.strength.domains, [.strength])
        XCTAssertEqual(AnalysisProfile.endurance.domains, [.endurance])
        XCTAssertEqual(AnalysisProfile.overallLoad.domains, [.strength, .endurance])
    }

    func testOnlyOverallLoadCoversBothDomains() {
        XCTAssertTrue(AnalysisProfile.overallLoad.coversBothDomains)
        XCTAssertFalse(AnalysisProfile.strength.coversBothDomains)
        XCTAssertFalse(AnalysisProfile.endurance.coversBothDomains)
    }

    func testCoversAnswersPerDomain() {
        XCTAssertTrue(AnalysisProfile.strength.covers(.strength))
        XCTAssertFalse(AnalysisProfile.strength.covers(.endurance))
        XCTAssertTrue(AnalysisProfile.endurance.covers(.endurance))
        XCTAssertFalse(AnalysisProfile.endurance.covers(.strength))
        for domain in AnalysisDomain.allCases {
            XCTAssertTrue(AnalysisProfile.overallLoad.covers(domain))
        }
    }

    /// The raw values are written into the store and into `UserDefaults`, so
    /// renaming a case is a migration and not a refactor.
    func testRawValuesAreStable() {
        XCTAssertEqual(AnalysisProfile.strength.rawValue, "strength")
        XCTAssertEqual(AnalysisProfile.endurance.rawValue, "endurance")
        XCTAssertEqual(AnalysisProfile.overallLoad.rawValue, "overallLoad")
    }

    func testDisplayNamesAreTheLabelsOnTheSegmentedControl() {
        XCTAssertEqual(AnalysisProfile.strength.displayName, "Strength")
        XCTAssertEqual(AnalysisProfile.endurance.displayName, "Endurance")
        XCTAssertEqual(AnalysisProfile.overallLoad.displayName, "Overall load")
    }

    // MARK: - Resolution

    func testAProfileTheWindowSupportsIsKept() {
        let window = [Self.session(.strength), Self.session(.run)]
        XCTAssertEqual(AnalysisProfile.strength.resolved(for: window), .strength)
        XCTAssertEqual(AnalysisProfile.endurance.resolved(for: window), .endurance)
        XCTAssertEqual(AnalysisProfile.overallLoad.resolved(for: window), .overallLoad)
    }

    /// A sync landing between the moment the picker was filled and the moment
    /// the user tapped must not buy an analysis of an empty page.
    func testAProfileWithoutASessionWidensToWhatTheWindowHolds() {
        let runsOnly = [Self.session(.run), Self.session(.ride)]
        XCTAssertEqual(AnalysisProfile.strength.resolved(for: runsOnly), .endurance)
        XCTAssertEqual(AnalysisProfile.endurance.resolved(for: runsOnly), .endurance)
    }

    /// The implicit profile of AC1: a Hevy-only window is a strength analysis,
    /// and is recorded as one although no picker was ever shown.
    func testOverallLoadNarrowsToTheOneDomainTheWindowHolds() {
        XCTAssertEqual(
            AnalysisProfile.overallLoad.resolved(for: [Self.session(.strength)]),
            .strength
        )
        XCTAssertEqual(
            AnalysisProfile.overallLoad.resolved(for: [Self.session(.run)]),
            .endurance
        )
    }

    func testAnEmptyWindowResolvesToOverallLoad() {
        for profile in AnalysisProfile.allCases {
            XCTAssertEqual(profile.resolved(for: []), .overallLoad)
        }
    }

    private static func session(_ kind: ActivityKind) -> WorkoutSummary {
        WorkoutSummary(
            id: "w-\(kind.rawValue)",
            title: kind.rawValue,
            startTime: reference,
            source: kind == .strength ? .hevy : .strava,
            kind: kind,
            volumeKg: kind == .strength ? 4_200 : 0,
            exerciseCount: kind == .strength ? 5 : 0,
            countedSetCount: kind == .strength ? 18 : 0,
            distanceMeters: kind == .strength ? nil : 8_400
        )
    }
}
