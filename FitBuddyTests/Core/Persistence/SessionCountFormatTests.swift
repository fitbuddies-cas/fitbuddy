import XCTest
@testable import FitBuddy

/// Unit tests for `SessionCountFormat` (US-15 AC4, #182): the breakdown of a
/// stored analysis survives a round trip, and a row written before the column
/// existed still renders.
final class SessionCountFormatTests: XCTestCase {
    private func context(
        sources: [ConnectorSource: Int],
        domains: [AnalysisDomain: Int]
    ) -> AnalysisContext {
        AnalysisContext(sessionCounts: sources, domainCounts: domains, window: .default)
    }

    func testBothBreakdownsSurviveTheRoundTrip() {
        let sources: [ConnectorSource: Int] = [.hevy: 14, .strava: 9, .polar: 2]
        // Not the source split: two of the Strava sessions were weight
        // training (ADR-012), which is what makes the second map worth storing.
        let domains: [AnalysisDomain: Int] = [.strength: 16, .endurance: 9]

        let decoded = SessionCountFormat.decode(
            SessionCountFormat.encode(context(sources: sources, domains: domains)),
            fallbackSessionCount: 25
        )

        XCTAssertEqual(decoded, SessionCountFormat.Counts(sources: sources, domains: domains))
    }

    /// The keys are the raw values of the enums, under named maps — a stored
    /// blob has to stay readable when a fourth source is inserted into
    /// `ConnectorSource`, and readable at all the first time it is debugged.
    func testCountsAreStoredUnderTheirRawValues() throws {
        let json = try XCTUnwrap(
            SessionCountFormat.encode(
                context(sources: [.hevy: 14, .strava: 9], domains: [.strength: 14, .endurance: 9])
            )
        )

        let raw = try JSONDecoder().decode([String: [String: Int]].self, from: json)

        XCTAssertEqual(raw["sources"], ["hevy": 14, "strava": 9])
        XCTAssertEqual(raw["domains"], ["strength": 14, "endurance": 9])
    }

    /// Nothing to store is stored as nothing: the row then falls back to its
    /// own total, which is written either way.
    func testAnEmptyBasisEncodesToNoBytes() {
        XCTAssertNil(SessionCountFormat.encode(context(sources: [:], domains: [:])))
    }

    /// The migration case (V4 and earlier). Every analysis before #182 was
    /// built from Hevy sessions alone, so the total belongs to Hevy — reading
    /// it as "no sessions" would blank the context line of every stored row.
    /// No domains are claimed; the caller derives them from the sources.
    func testAMissingBlobReadsAsTheRowsOwnHevyTotal() {
        let counts = SessionCountFormat.decode(nil, fallbackSessionCount: 12)

        XCTAssertEqual(counts.sources, [.hevy: 12])
        XCTAssertNil(counts.domains)
    }

    /// A row from before #36 recorded no count at all; there is nothing to
    /// attribute, and `AnalysisContext` reports it as thin.
    func testAMissingBlobWithoutATotalReadsAsEmpty() {
        XCTAssertEqual(
            SessionCountFormat.decode(nil, fallbackSessionCount: 0),
            SessionCountFormat.Counts(sources: [:], domains: nil)
        )
    }

    /// Bytes that are not a breakdown must not take the history down with
    /// them: the row keeps the line it can still justify.
    func testUnreadableBytesFallBackToTheTotal() {
        let json = Data("not a session count map".utf8)

        XCTAssertEqual(SessionCountFormat.decode(json, fallbackSessionCount: 7).sources, [.hevy: 7])
    }

    /// A blob written by a build that counted sources only: the line is
    /// restored, and the domains are left to the caller to derive.
    func testABlobWithoutDomainsLeavesThemToTheCaller() throws {
        let json = try JSONEncoder().encode(["sources": ["hevy": 14, "strava": 9]])

        let counts = SessionCountFormat.decode(json, fallbackSessionCount: 23)

        XCTAssertEqual(counts.sources, [.hevy: 14, .strava: 9])
        XCTAssertNil(counts.domains)
    }

    /// A blob written by a build with a fourth connector: the known counts are
    /// kept, the unknown one is dropped, and the row stays open.
    func testAnUnknownSourceKeyIsDroppedRatherThanFailingTheRead() throws {
        let json = try JSONEncoder().encode(["sources": ["hevy": 14, "garmin": 3]])

        XCTAssertEqual(SessionCountFormat.decode(json, fallbackSessionCount: 17).sources, [.hevy: 14])
    }

    /// The same for a domain this build has no name for — #185's profiles may
    /// add one.
    func testAnUnknownDomainKeyIsDroppedRatherThanFailingTheRead() throws {
        let json = try JSONEncoder().encode([
            "sources": ["hevy": 14],
            "domains": ["strength": 14, "mobility": 3],
        ])

        XCTAssertEqual(SessionCountFormat.decode(json, fallbackSessionCount: 14).domains, [.strength: 14])
    }
}
