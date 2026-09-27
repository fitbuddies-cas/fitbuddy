import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisContext` (US-6, #36; US-15 AC4, #182): the
/// thin-data rule of AC2, now judged per domain, and the per-source basis
/// line.
final class AnalysisContextTests: XCTestCase {
    private func context(sessions: Int, weeks: Int = 4) -> AnalysisContext {
        AnalysisContext(sessionCount: sessions, window: AnalysisWindow(weeks: weeks))
    }

    private func context(_ counts: [ConnectorSource: Int], weeks: Int = 4) -> AnalysisContext {
        AnalysisContext(sessionCounts: counts, window: AnalysisWindow(weeks: weeks))
    }

    private func context(
        _ counts: [ConnectorSource: Int],
        domains: [AnalysisDomain: Int]
    ) -> AnalysisContext {
        AnalysisContext(sessionCounts: counts, domainCounts: domains, window: .default)
    }

    // MARK: - Thin data (US-6 AC2, US-15 AC4)

    /// The boundary itself, from both sides: US-6 AC2 says "fewer than 5", so
    /// five sessions is the first count that is no longer thin.
    func testThinDataEndsAtTheThreshold() {
        XCTAssertTrue(context(sessions: AnalysisContext.thinDataThreshold - 1).isThin)
        XCTAssertFalse(context(sessions: AnalysisContext.thinDataThreshold).isThin)
    }

    /// A window with nothing in it never reaches the view — the run fails with
    /// `.noTrainingData` first — but the rule must not invert if it ever does.
    func testEmptyWindowIsThin() {
        XCTAssertTrue(context(sessions: 0).isThin)
    }

    /// The widened window of #87 does not change the rule: four sessions
    /// spread over 13 weeks are thinner still, not less thin.
    func testThinDataRuleIgnoresTheWindowLength() {
        XCTAssertTrue(context(sessions: 4, weeks: 13).isThin)
        XCTAssertFalse(context(sessions: 12, weeks: 13).isThin)
    }

    /// The point of the split (US-15 AC4): eight sessions look solid as a
    /// total, and neither half of them supports a recommendation.
    func testADomainBelowTheThresholdIsThinEvenWhenTheTotalIsNot() {
        let sut = context([.hevy: 4, .strava: 4])

        XCTAssertTrue(sut.isThin)
        XCTAssertEqual(sut.thinDomains, [.strength, .endurance])
    }

    /// A source that delivered nothing is not a thin domain, it is a domain
    /// the analysis is not about — someone with Hevy alone must not be warned
    /// about missing runs.
    func testADomainWithoutSessionsIsNotThin() {
        let sut = context([.hevy: 12])

        XCTAssertFalse(sut.isThin)
        XCTAssertEqual(sut.thinDomains, [])
        XCTAssertNil(sut.thinDataWarning)
    }

    /// Strava and Polar are one domain, so their sessions are added up before
    /// the threshold is applied — three runs and three rides are six endurance
    /// sessions, not two thin sources.
    func testEnduranceSourcesAreCountedTogetherAgainstTheThreshold() {
        XCTAssertFalse(context([.hevy: 9, .strava: 3, .polar: 3]).isThin)
        XCTAssertEqual(context([.hevy: 9, .strava: 2, .polar: 2]).thinDomains, [.endurance])
    }

    /// The domain is what a session *was*, not where it came from (ADR-012):
    /// five Strava weight-training sessions are strength data, however the
    /// line names them.
    func testTheDomainsAreCountedApartFromTheSources() {
        let sut = context([.hevy: 3, .strava: 7], domains: [.strength: 8, .endurance: 2])

        XCTAssertEqual(sut.basisDescription, "3 Hevy · 7 Strava sessions")
        XCTAssertEqual(sut.sessionCount(in: .strength), 8)
        XCTAssertEqual(sut.thinDomains, [.endurance])
    }

    /// A basis that only ever counted sources — a stored row from before #182,
    /// or a fixture — reads its domains off them, as that run meant them.
    func testDomainsAreDerivedFromTheSourcesWhenNoneWereRecorded() {
        let sut = context([.hevy: 14, .strava: 6, .polar: 3])

        XCTAssertEqual(sut.domainCounts, [.strength: 14, .endurance: 9])
    }

    /// The rule the review settled on, and the shape #185 brings back: where
    /// the analysis covered less of the window than the line counts — under a
    /// profile, or while the prompt filtered by source before #183 — US-6 AC2
    /// is about what the model saw, not about what the app read.
    func testADomainIsThinOnWhatReachedThePromptAndNotOnTheWholeWindow() {
        let sut = AnalysisContext(
            sessionCounts: [.hevy: 3, .strava: 3],
            domainCounts: [.strength: 6],
            analysedCounts: [.strength: 3],
            window: .default
        )

        XCTAssertEqual(sut.basisDescription, "3 Hevy · 3 Strava sessions")
        XCTAssertTrue(sut.isThin)
        XCTAssertEqual(
            sut.thinDataWarning,
            "Thin strength data — 3 sessions. Treat the recommendation as a starting point."
        )
    }

    /// The other half of that rule: a single run next to fourteen lifts must
    /// not put a thin-endurance warning on a recommendation with no endurance
    /// content in it — the analysis never covered endurance.
    func testADomainTheAnalysisDidNotCoverIsNotWarnedAbout() {
        let sut = AnalysisContext(
            sessionCounts: [.hevy: 14, .strava: 1],
            domainCounts: [.strength: 14, .endurance: 1],
            analysedCounts: [.strength: 14],
            window: .default
        )

        XCTAssertEqual(sut.basisDescription, "14 Hevy · 1 Strava sessions")
        XCTAssertEqual(sut.analysedDomains, [.strength])
        XCTAssertFalse(sut.isThin)
        XCTAssertNil(sut.thinDataWarning)
    }

    /// A basis whose breakdown did not survive keeps its total and is judged
    /// on it: twenty-three sessions are not thin, and there is no domain the
    /// warning could honestly name.
    func testAnUnattributedBasisIsJudgedOnItsTotal() {
        let sut = AnalysisContext(unattributedSessionCount: 23, window: .default)

        XCTAssertEqual(sut.basisDescription, "23 sessions")
        XCTAssertEqual(sut.countedSources, [])
        XCTAssertFalse(sut.isThin)
        XCTAssertTrue(AnalysisContext(unattributedSessionCount: 3, window: .default).isThin)
    }

    // MARK: - Widened window (#87)

    /// The note names no domain since #183: the ladder resolves over every
    /// session, because every session reaches the prompt, so "held no
    /// sessions" is exactly what widening the window means again. The
    /// qualifier #182 added was true only while the two disagreed.
    func testTheWidenedWindowNoteNamesNoDomain() {
        let sut = AnalysisContext(
            sessionCounts: [.hevy: 1, .strava: 12],
            domainCounts: [.strength: 1, .endurance: 12],
            window: AnalysisWindow(weeks: 8)
        )

        XCTAssertEqual(sut.basisDescription, "1 Hevy · 12 Strava sessions")
        XCTAssertEqual(
            sut.widenedWindowNote,
            "This analysis covered 8 weeks — its most recent 4 held no sessions."
        )
    }

    /// The default window needs no explaining.
    func testTheDefaultWindowHasNoNote() {
        XCTAssertNil(context(sessions: 12).widenedWindowNote)
    }

    // MARK: - Thin data wording

    /// AC4: the warning says which half of the training it is about, so the
    /// user knows what to read the recommendation cautiously about.
    func testThinDataWarningNamesTheThinDomain() {
        let sut = context([.hevy: 14, .strava: 3])

        XCTAssertEqual(
            sut.thinDataWarning,
            "Thin endurance data — 3 sessions. Treat the recommendation as a starting point."
        )
    }

    /// Both halves thin: both are named, in a fixed order, rather than the
    /// line falling back to a vague total.
    func testThinDataWarningNamesBothDomains() {
        let sut = context([.hevy: 3, .strava: 1])

        XCTAssertEqual(
            sut.thinDataWarning,
            """
            Thin strength data — 3 sessions · Thin endurance data — 1 session. \
            Treat the recommendation as a starting point.
            """
        )
    }

    /// A basis nobody recorded — a stored row from before #36 — has no domain
    /// to name and still has to warn.
    func testThinDataWarningFallsBackToTheTotalWithoutACountedDomain() {
        XCTAssertEqual(
            context(sessions: 0).thinDataWarning,
            "Thin data — fewer than 5 sessions. Treat the recommendation as a starting point."
        )
    }

    // MARK: - Basis line (US-6 AC1, US-15 AC4)

    /// AC "only Hevy connected → the line reads as it does today".
    func testASingleSourceReadsAsBeforeTheSplit() {
        XCTAssertEqual(context(sessions: 12).basisDescription, "12 Hevy sessions")
        XCTAssertEqual(context(sessions: 12).countedSources, [.hevy])
    }

    /// The example of #182, and the stable order it asks for: a dictionary has
    /// no order of its own, so the line follows `ConnectorSource.allCases`.
    func testTwoSourcesAreNamedSeparatelyInAFixedOrder() {
        XCTAssertEqual(context([.strava: 9, .hevy: 14]).basisDescription, "14 Hevy · 9 Strava sessions")
        XCTAssertEqual(context([.hevy: 14, .strava: 9]).basisDescription, "14 Hevy · 9 Strava sessions")
        XCTAssertEqual(context([.hevy: 14, .strava: 9]).countedSources, [.hevy, .strava])
    }

    func testAllThreeSourcesAreNamedInTheOrderOfTheConnectorList() {
        let sut = context([.polar: 2, .hevy: 14, .strava: 9])

        XCTAssertEqual(sut.basisDescription, "14 Hevy · 9 Strava · 2 Polar sessions")
        XCTAssertEqual(sut.sessionCount, 25)
    }

    /// A connector the user linked but did not use must not appear as
    /// "0 Polar": an untouched source would read as a considered input.
    func testSourcesWithoutSessionsAreLeftOut() {
        let sut = context([.hevy: 14, .strava: 0, .polar: 0])

        XCTAssertEqual(sut.basisDescription, "14 Hevy sessions")
        XCTAssertEqual(sut.countedSources, [.hevy])
        XCTAssertEqual(sut.sessionCounts, [.hevy: 14])
    }

    /// The noun is carried once, at the end, and follows the total.
    func testTheSessionNounFollowsTheTotal() {
        XCTAssertEqual(context(sessions: 1).basisDescription, "1 Hevy session")
        XCTAssertEqual(context([.hevy: 1, .strava: 1]).basisDescription, "1 Hevy · 1 Strava sessions")
    }

    /// The basis of a run that recorded no count, which the view still has to
    /// render rather than print "Based on  sessions".
    func testAnEmptyBasisStillNamesItsZero() {
        XCTAssertEqual(context([:]).basisDescription, "0 sessions")
        XCTAssertEqual(context([:]).sessionCount, 0)
    }

    // MARK: - Counting (US-15 AC4, #182)

    private static let reference = Date(timeIntervalSince1970: 1_788_000_000)

    private static func summary(
        daysAgo: Int,
        source: ConnectorSource = .hevy,
        kind: ActivityKind = .strength
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: "w-\(daysAgo)",
            title: "Session",
            startTime: reference.addingTimeInterval(-Double(daysAgo) * 86_400),
            source: source,
            kind: kind,
            volumeKg: source == .hevy ? 4_200 : 0,
            exerciseCount: 5,
            countedSetCount: 18,
            distanceMeters: source.isEnduranceSource ? 8_400 : nil
        )
    }

    /// The domain follows the normalized sport, not the connector (ADR-012):
    /// a Strava `WeightTraining` session is named under Strava on the line and
    /// counted as strength in the warning.
    func testTheDomainSplitFollowsTheSportAndNotTheSource() {
        let summaries = [
            Self.summary(daysAgo: 2),
            Self.summary(daysAgo: 3, source: .strava, kind: .strength),
            Self.summary(daysAgo: 4, source: .strava, kind: .run),
        ]

        let counts = AnalysisContext.counts(
            in: summaries,
            from: Self.reference.addingTimeInterval(-28 * 86_400)
        )

        XCTAssertEqual(counts.sources, [.hevy: 1, .strava: 2])
        XCTAssertEqual(counts.domains, [.strength: 2, .endurance: 1])
    }

    // MARK: - Totals

    /// `sessionCount` stays the sum, so everything written against it before
    /// #182 keeps meaning what it did.
    func testSessionCountIsTheSumOverTheSources() {
        let sut = context([.hevy: 14, .strava: 9, .polar: 2])

        XCTAssertEqual(sut.sessionCount, 25)
        XCTAssertEqual(sut.sessionCount(from: .strava), 9)
        XCTAssertEqual(context([.hevy: 14, .strava: 9]).sessionCount(from: .polar), 0)
        XCTAssertEqual(sut.sessionCount(in: .strength), 14)
        XCTAssertEqual(sut.sessionCount(in: .endurance), 11)
    }

    /// Two contexts describing the same empty window compare equal however
    /// their counts were written — the restore path reads `[:]` where the live
    /// run passed `[.hevy: 0]`.
    func testZeroCountsDoNotMakeTwoEmptyBasesUnequal() {
        XCTAssertEqual(context([.hevy: 0]), context([:]))
    }
}
