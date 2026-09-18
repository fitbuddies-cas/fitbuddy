import XCTest
@testable import FitBuddy

/// Unit tests for `SessionCountFormat` (US-15 AC4, #182): the breakdown of a
/// stored analysis survives a round trip, a row written before the column
/// existed still renders, and a row this build cannot read keeps its total
/// without claiming a source.
final class SessionCountFormatTests: XCTestCase {
    private func context(
        sources: [ConnectorSource: Int],
        domains: [AnalysisDomain: Int],
        analysed: [AnalysisDomain: Int]? = nil
    ) -> AnalysisContext {
        AnalysisContext(
            sessionCounts: sources,
            domainCounts: domains,
            analysedCounts: analysed,
            window: .default
        )
    }

    func testAllThreeBreakdownsSurviveTheRoundTrip() {
        let sources: [ConnectorSource: Int] = [.hevy: 14, .strava: 9, .polar: 2]
        // Not the source split: two of the Strava sessions were weight
        // training (ADR-012), which is what makes the second map worth storing.
        let domains: [AnalysisDomain: Int] = [.strength: 16, .endurance: 9]
        // And of those, only Hevy's reached the prompt for now.
        let analysed: [AnalysisDomain: Int] = [.strength: 14]

        let decoded = SessionCountFormat.decode(
            SessionCountFormat.encode(context(sources: sources, domains: domains, analysed: analysed)),
            fallbackSessionCount: 25
        )

        XCTAssertEqual(
            decoded,
            .breakdown(sources: sources, domains: domains, analysed: analysed)
        )
    }

    /// The keys are the raw values of the enums, under named maps — a stored
    /// blob has to stay readable when a fourth source is inserted into
    /// `ConnectorSource`, and readable at all the first time it is debugged.
    func testCountsAreStoredUnderTheirRawValues() throws {
        let json = try XCTUnwrap(
            SessionCountFormat.encode(
                context(
                    sources: [.hevy: 14, .strava: 9],
                    domains: [.strength: 14, .endurance: 9],
                    analysed: [.strength: 14]
                )
            )
        )

        let raw = try JSONDecoder().decode([String: [String: Int]].self, from: json)

        XCTAssertEqual(raw["sources"], ["hevy": 14, "strava": 9])
        XCTAssertEqual(raw["domains"], ["strength": 14, "endurance": 9])
        XCTAssertEqual(raw["analysed"], ["strength": 14])
    }

    /// Nothing to store is stored as nothing: the row then falls back to its
    /// own total, which is written either way.
    func testAnEmptyBasisEncodesToNoBytes() {
        XCTAssertNil(SessionCountFormat.encode(context(sources: [:], domains: [:])))
    }

    /// The migration case (V4 and earlier). Every analysis before #182 was
    /// built from Hevy sessions alone, so the total belongs to Hevy — reading
    /// it as "no sessions" would blank the context line of every stored row.
    /// Neither breakdown is claimed; the caller derives them.
    func testAMissingBlobReadsAsTheRowsOwnHevyTotal() {
        XCTAssertEqual(
            SessionCountFormat.decode(nil, fallbackSessionCount: 12),
            .breakdown(sources: [.hevy: 12], domains: nil, analysed: nil)
        )
    }

    /// A row from before #36 recorded no count at all; there is nothing to
    /// attribute, and `AnalysisContext` reports it as thin.
    func testAMissingBlobWithoutATotalReadsAsEmpty() {
        XCTAssertEqual(
            SessionCountFormat.decode(nil, fallbackSessionCount: 0),
            .breakdown(sources: [:], domains: nil, analysed: nil)
        )
    }

    /// Bytes that are not a breakdown must not take the history down with
    /// them, and must not be attributed to Hevy either: a row of three lifts
    /// and twenty runs would come back as "23 Hevy sessions".
    func testUnreadableBytesKeepTheTotalWithoutClaimingASource() {
        let json = Data("not a session count map".utf8)

        XCTAssertEqual(SessionCountFormat.decode(json, fallbackSessionCount: 23), .unattributed(23))
    }

    /// A blob written by a build that counted sources only: the line is
    /// restored, and both finer breakdowns are left to the caller to derive.
    func testABlobWithoutDomainsLeavesThemToTheCaller() throws {
        let json = try JSONEncoder().encode(["sources": ["hevy": 14, "strava": 9]])

        XCTAssertEqual(
            SessionCountFormat.decode(json, fallbackSessionCount: 23),
            .breakdown(sources: [.hevy: 14, .strava: 9], domains: nil, analysed: nil)
        )
    }

    /// A blob written by a build with a fourth connector. Keeping the known
    /// keys and dropping the unknown one would render 14 of 17 sessions as the
    /// whole basis, so the row keeps its total and names no source at all.
    func testAnUnknownSourceKeyFallsBackToTheTotal() throws {
        let json = try JSONEncoder().encode(["sources": ["hevy": 14, "garmin": 3]])

        XCTAssertEqual(SessionCountFormat.decode(json, fallbackSessionCount: 17), .unattributed(17))
    }

    /// The same for a domain this build has no name for — #185's profiles may
    /// add one.
    func testAnUnknownDomainKeyFallsBackToTheTotal() throws {
        let json = try JSONEncoder().encode([
            "sources": ["hevy": 17],
            "domains": ["strength": 14, "mobility": 3],
        ])

        XCTAssertEqual(SessionCountFormat.decode(json, fallbackSessionCount: 17), .unattributed(17))
    }
}
