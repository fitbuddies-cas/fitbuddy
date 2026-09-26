import XCTest
@testable import FitBuddy

/// Stage 5 of `AnalysisVerdictRule` (#246): the effort cap of ADR-014 §3,
/// scale by scale as ADR-015 binds it.
///
/// Every number asserted here is the ADR's: 3 weeks, 130 %, 80 %. The
/// preceding weeks' mean is 10 throughout, so a last-seven-days mean of 13 is
/// exactly 130 % and 8 exactly 80 %.
final class AnalysisVerdictRuleEffortTests: XCTestCase {
    // MARK: - Thresholds

    func testTheThresholdsAreTheOnesTheADRNames() {
        XCTAssertEqual(AnalysisVerdictRule.effortQualifyingWeeks, 3)
        XCTAssertEqual(AnalysisVerdictRule.effortRisingRatio, 1.30)
        XCTAssertEqual(AnalysisVerdictRule.effortFallingRatio, 0.80)
    }

    func testAboveOneHundredThirtyPercentIsRising() {
        XCTAssertEqual(AnalysisVerdictRule.trend(of: series(.hevyRPE, recent: 13.1)), .rising)
    }

    /// "Über 130 %": exactly 130 % is not above it.
    func testExactlyOneHundredThirtyPercentIsStable() {
        XCTAssertEqual(AnalysisVerdictRule.trend(of: series(.hevyRPE, recent: 13)), .stable)
    }

    /// "Unter 80 %": exactly 80 % is not below it.
    func testExactlyEightyPercentIsStable() {
        XCTAssertEqual(AnalysisVerdictRule.trend(of: series(.hevyRPE, recent: 8)), .stable)
    }

    func testBelowEightyPercentIsFalling() {
        XCTAssertEqual(AnalysisVerdictRule.trend(of: series(.hevyRPE, recent: 7.9)), .falling)
    }

    // MARK: - Qualification (ADR-014 §3.3)

    func testThreeWeeksWithTheLastSevenDaysQualify() {
        let threeWeeks = EffortSeries(scale: .hevyRPE, valuesByWeek: [0: [20], 1: [10], 3: [10]])

        XCTAssertEqual(AnalysisVerdictRule.trend(of: threeWeeks), .rising)
    }

    func testTwoWeeksDoNotQualify() {
        let twoWeeks = EffortSeries(scale: .hevyRPE, valuesByWeek: [0: [20], 1: [10, 10, 10]])

        XCTAssertNil(AnalysisVerdictRule.trend(of: twoWeeks))
    }

    /// Many values in few weeks are still few weeks.
    func testManyValuesInOneWeekCountAsOneWeek() {
        let oneWeek = EffortSeries(scale: .hevyRPE, valuesByWeek: [0: [20, 20, 20, 20, 20]])

        XCTAssertNil(AnalysisVerdictRule.trend(of: oneWeek))
    }

    func testThreeWeeksWithoutTheLastSevenDaysDoNotQualify() {
        let noRecent = EffortSeries(scale: .hevyRPE, valuesByWeek: [1: [10], 2: [10], 3: [10]])

        XCTAssertNil(AnalysisVerdictRule.trend(of: noRecent))
    }

    /// An unqualified scale is ignored, not filled: its steep rise caps
    /// nothing.
    func testAnUnqualifiedRisingScaleDoesNotCap() {
        let twoWeeks = EffortSeries(scale: .hevyRPE, valuesByWeek: [0: [30], 1: [10]])

        XCTAssertEqual(
            AnalysisVerdictRule.outcome(for: evidence(effort: [twoWeeks])),
            .init(verdict: .progress, reason: .latestIsWindowBest)
        )
    }

    // MARK: - The cap

    func testARisingScaleTurnsProgressIntoHold() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(effort: [series(.hevyRPE, recent: 13.1)]))

        XCTAssertEqual(outcome, .init(verdict: .hold, reason: .effortRising))
    }

    func testAStableScaleLeavesProgress() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(effort: [series(.hevyRPE, recent: 13)]))

        XCTAssertEqual(outcome, .init(verdict: .progress, reason: .latestIsWindowBest))
    }

    /// Falling effort promotes nothing and lowers nothing.
    func testAFallingScaleLeavesEveryVerdictAsItWas() {
        let falling = [series(.hevyRPE, recent: 5)]

        XCTAssertEqual(
            AnalysisVerdictRule.outcome(for: evidence(effort: falling)),
            .init(verdict: .progress, reason: .latestIsWindowBest)
        )
        XCTAssertEqual(
            AnalysisVerdictRule.outcome(for: evidence(exercises: [exercise(isPlateaued: true)], effort: falling)),
            .init(verdict: .hold, reason: .plateauMajority)
        )
    }

    /// ADR-014 §3.2: scales are read one by one and never set against each
    /// other — one rising scale caps although another falls.
    func testOneRisingScaleCapsWhateverTheOthersDo() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(
            analysisProfile: .overallLoad,
            effort: [
                series(.hevyRPE, recent: 5),
                series(.stravaRelativeEffort, recent: 10),
                series(.polarCardioLoad, recent: 5),
                series(.polarPerceivedLoad, recent: 13.1),
            ]
        ))

        XCTAssertEqual(outcome, .init(verdict: .hold, reason: .effortRising))
    }

    /// Two scales of the same provider are two scales (ADR-015 §1): Polar's
    /// perceived load falling does not offset its cardio load rising.
    func testTwoPolarScalesAreReadApart() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(
            analysisProfile: .endurance,
            exercises: [],
            effort: [series(.polarCardioLoad, recent: 13.1), series(.polarPerceivedLoad, recent: 5)]
        ))

        XCTAssertEqual(outcome, .init(verdict: .hold, reason: .effortRising))
    }

    /// Effort never produces `recover` (ADR-014 §3.5), and a `recover` from
    /// the rest gate stays one.
    func testRecoverIsUntouched() {
        let outcome = AnalysisVerdictRule.outcome(
            for: evidence(trainingDays: 6, effort: [series(.hevyRPE, recent: 30)])
        )

        XCTAssertEqual(outcome, .init(verdict: .recover, reason: .restDays))
    }

    func testAHoldKeepsTheStageThatProducedIt() {
        let rising = [series(.hevyRPE, recent: 30)]

        XCTAssertEqual(
            AnalysisVerdictRule.outcome(for: evidence(exercises: [exercise(isPlateaued: true)], effort: rising)),
            .init(verdict: .hold, reason: .plateauMajority)
        )
        XCTAssertEqual(
            AnalysisVerdictRule.outcome(for: evidence(exercises: [exercise()], effort: rising)),
            .init(verdict: .hold, reason: .noNewBest)
        )
    }

    // MARK: - insufficientData (ADR-014 §2 row 5, product decision on #246)

    /// The data gates say the data carries nothing. A rising scale does not
    /// change that.
    func testTheDataGatesStayInsufficientData() {
        let rising = [series(.hevyRPE, recent: 30), series(.stravaRelativeEffort, recent: 30)]

        XCTAssertEqual(
            AnalysisVerdictRule.outcome(for: evidence(sessionsInWindow: 3, effort: rising)),
            .init(verdict: .insufficientData, reason: .tooFewSessions)
        )
        XCTAssertEqual(
            AnalysisVerdictRule.outcome(for: evidence(sessionsInLastSevenDays: 0, effort: rising)),
            .init(verdict: .insufficientData, reason: .noRecentSession)
        )
        XCTAssertEqual(
            AnalysisVerdictRule.outcome(for: evidence(exercises: [exercise(points: 3)], effort: rising)),
            .init(verdict: .insufficientData, reason: .plateauUndecidable)
        )
    }

    /// The same gates under "Endurance".
    func testTheDataGatesStayInsufficientDataUnderEndurance() {
        let rising = [series(.stravaRelativeEffort, recent: 30)]

        XCTAssertEqual(
            AnalysisVerdictRule.outcome(
                for: evidence(analysisProfile: .endurance, sessionsInWindow: 3, exercises: [], effort: rising)
            ),
            .init(verdict: .insufficientData, reason: .tooFewSessions)
        )
        XCTAssertEqual(
            AnalysisVerdictRule.outcome(
                for: evidence(analysisProfile: .endurance, sessionsInLastSevenDays: 0, exercises: [], effort: rising)
            ),
            .init(verdict: .insufficientData, reason: .noRecentSession)
        )
    }

    /// ADR-014 §5: under "Endurance" the `insufficientData` that only says
    /// "no strength stages here" becomes the `hold` of stage 5.
    func testARisingEnduranceScaleGivesEnduranceItsHold() {
        for scale in [EffortScale.stravaRelativeEffort, .polarCardioLoad, .polarPerceivedLoad, .polarMuscleLoad] {
            let outcome = AnalysisVerdictRule.outcome(
                for: evidence(analysisProfile: .endurance, exercises: [], effort: [series(scale, recent: 13.1)])
            )

            XCTAssertEqual(outcome, .init(verdict: .hold, reason: .effortRising), scale.rawValue)
        }
    }

    func testAStableEnduranceScaleLeavesEnduranceWithoutAVerdict() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(
            analysisProfile: .endurance,
            exercises: [],
            effort: [series(.stravaRelativeEffort, recent: 13), series(.polarCardioLoad, recent: 5)]
        ))

        XCTAssertEqual(outcome, .init(verdict: .insufficientData, reason: .noStrengthDomain))
    }

    /// Still no `progress` under "Endurance" (ADR-014 §5): effort only caps.
    func testEnduranceStillCannotProgress() {
        let verdicts = [5.0, 10, 13, 13.1, 30].map { recent in
            AnalysisVerdictRule.outcome(for: evidence(
                analysisProfile: .endurance,
                exercises: [],
                effort: [series(.stravaRelativeEffort, recent: recent)]
            )).verdict
        }

        XCTAssertEqual(verdicts, [.insufficientData, .insufficientData, .insufficientData, .hold, .hold])
    }

    // MARK: - Domain binding (ADR-014 §5)

    /// "Strength" reads Hevy's RPE and nothing else.
    func testStrengthReadsOnlyTheHevyRPE() {
        for scale in [EffortScale.stravaRelativeEffort, .polarCardioLoad, .polarPerceivedLoad, .polarMuscleLoad] {
            let outcome = AnalysisVerdictRule.outcome(
                for: evidence(analysisProfile: .strength, effort: [series(scale, recent: 30)])
            )

            XCTAssertEqual(outcome, .init(verdict: .progress, reason: .latestIsWindowBest), scale.rawValue)
        }
        XCTAssertEqual(
            AnalysisVerdictRule.outcome(
                for: evidence(analysisProfile: .strength, effort: [series(.hevyRPE, recent: 30)])
            ),
            .init(verdict: .hold, reason: .effortRising)
        )
    }

    /// "Endurance" does not read Hevy's RPE.
    func testEnduranceDoesNotReadTheHevyRPE() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(
            analysisProfile: .endurance,
            exercises: [],
            effort: [series(.hevyRPE, recent: 30)]
        ))

        XCTAssertEqual(outcome, .init(verdict: .insufficientData, reason: .noStrengthDomain))
    }

    /// "Overall load" reads every scale.
    func testOverallLoadReadsEveryScale() {
        for scale in EffortScale.allCases {
            let outcome = AnalysisVerdictRule.outcome(
                for: evidence(analysisProfile: .overallLoad, effort: [series(scale, recent: 30)])
            )

            XCTAssertEqual(outcome, .init(verdict: .hold, reason: .effortRising), scale.rawValue)
        }
    }

    func testTheBindingIsTheOneTheADRNames() {
        XCTAssertEqual(EffortScale.allCases.filter { $0.isRead(under: .strength) }, [.hevyRPE])
        XCTAssertEqual(
            EffortScale.allCases.filter { $0.isRead(under: .endurance) },
            [.stravaRelativeEffort, .polarCardioLoad, .polarPerceivedLoad, .polarMuscleLoad]
        )
        XCTAssertEqual(EffortScale.allCases.filter { $0.isRead(under: .overallLoad) }, EffortScale.allCases)
    }

    // MARK: - No effort data (AC5, ADR-014 §4)

    /// The ordinary case: nothing recorded, and the tree answers exactly as it
    /// did before stage 5 — at every stage.
    func testWithoutEffortDataEveryStageAnswersAsBefore() {
        let cases: [(AnalysisReportEvidence, AnalysisVerdictRule.Outcome)] = [
            (evidence(trainingDays: 6), .init(verdict: .recover, reason: .restDays)),
            (evidence(sessionsInWindow: 3), .init(verdict: .insufficientData, reason: .tooFewSessions)),
            (evidence(sessionsInLastSevenDays: 0), .init(verdict: .insufficientData, reason: .noRecentSession)),
            (
                evidence(analysisProfile: .endurance, exercises: []),
                .init(verdict: .insufficientData, reason: .noStrengthDomain)
            ),
            (
                evidence(exercises: [exercise(points: 3)]),
                .init(verdict: .insufficientData, reason: .plateauUndecidable)
            ),
            (evidence(exercises: [exercise(isPlateaued: true)]), .init(verdict: .hold, reason: .plateauMajority)),
            (evidence(), .init(verdict: .progress, reason: .latestIsWindowBest)),
            (evidence(exercises: [exercise()]), .init(verdict: .hold, reason: .noNewBest)),
        ]
        for (evidence, expected) in cases {
            XCTAssertTrue(evidence.effort.isEmpty)
            XCTAssertEqual(AnalysisVerdictRule.outcome(for: evidence), expected)
        }
    }

    /// Nothing recorded is not "moderate": the rule does not invent a series
    /// for a scale that has none, so a single recorded scale is read alone.
    func testAScaleWithoutValuesIsNotAssumed() {
        let onlyStrava = [series(.stravaRelativeEffort, recent: 13)]

        XCTAssertEqual(
            AnalysisVerdictRule.outcome(for: evidence(analysisProfile: .overallLoad, effort: onlyStrava)),
            .init(verdict: .progress, reason: .latestIsWindowBest)
        )
    }

    // MARK: - The lead of a capped report

    /// A strength report the cap turned from `progress` into `hold` gets the
    /// effort-cap lead, not the weights-only `holdLead` (#246, PO decision).
    func testAStrengthCapShowsTheEffortCapLead() {
        let validated = AnalysisReportValidator.validate(
            modelReport(verdict: .progress),
            against: evidence(effort: [series(.hevyRPE, recent: 13.1)])
        )

        XCTAssertEqual(validated.verdict, .hold)
        XCTAssertEqual(validated.headline, AnalysisReportValidator.holdHeadline)
        XCTAssertEqual(validated.lead, AnalysisReportValidator.effortCapLead)
    }

    /// A runner under "Endurance" gets the same lead — `holdLead` speaks of
    /// weights they never lifted.
    func testAnEnduranceCapShowsTheEffortCapLead() {
        let validated = AnalysisReportValidator.validate(
            modelReport(verdict: .progress),
            against: evidence(
                analysisProfile: .endurance,
                exercises: [],
                effort: [series(.stravaRelativeEffort, recent: 13.1)]
            )
        )

        XCTAssertEqual(validated.verdict, .hold)
        XCTAssertEqual(validated.headline, AnalysisReportValidator.holdHeadline)
        XCTAssertEqual(validated.lead, AnalysisReportValidator.effortCapLead)
    }

    /// A hold from the plateau majority keeps `holdLead`, even with a rising
    /// scale in the evidence: the effort-cap lead belongs to stage 5 only.
    func testAPlateauHoldKeepsTheHoldLead() {
        let validated = AnalysisReportValidator.validate(
            modelReport(verdict: .progress),
            against: evidence(
                exercises: [exercise(isPlateaued: true)],
                effort: [series(.hevyRPE, recent: 30)]
            )
        )

        XCTAssertEqual(validated.verdict, .hold)
        XCTAssertEqual(validated.lead, AnalysisReportValidator.holdLead)
    }

    func testTheEffortCapLeadIsTheProductOwnersText() {
        XCTAssertEqual(
            AnalysisReportValidator.effortCapLead,
            "Your recorded effort has risen against your own earlier weeks. "
                + "Hold your current training before adding more."
        )
    }

    // MARK: - Fixtures

    private func modelReport(verdict: AnalysisVerdict) -> AnalysisReport {
        AnalysisReport(headline: "Headline", verdict: verdict, lead: "Lead", cards: [], summary: "Summary")
    }

    /// A qualified series: 10 in weeks 1 and 2, `recent` in the last seven
    /// days.
    private func series(_ scale: EffortScale, recent: Double) -> EffortSeries {
        EffortSeries(scale: scale, valuesByWeek: [0: [recent], 1: [10], 2: [10]])
    }

    private func exercise(
        points: Int = 5,
        isPlateaued: Bool = false,
        latestIsWindowBest: Bool = false
    ) -> ListedExercise {
        ListedExercise(
            title: "Bench Press",
            muscleGroup: .chest,
            workingSet: WorkingSet(weightKg: 60, reps: 5),
            smallestStepKg: 2.5,
            progressionPoints: points,
            isPlateaued: isPlateaued,
            latestIsWindowBest: latestIsWindowBest
        )
    }

    /// Evidence that reaches `progress` at stage 4 unless a test says
    /// otherwise, so every cap test starts from the verdict it caps.
    private func evidence(
        analysisProfile: AnalysisProfile = .strength,
        trainingDays: Int = 3,
        sessionsInWindow: Int = 12,
        sessionsInLastSevenDays: Int = 3,
        exercises: [ListedExercise]? = nil,
        effort: [EffortSeries] = []
    ) -> AnalysisReportEvidence {
        AnalysisReportEvidence(
            exercises: exercises ?? [exercise(latestIsWindowBest: true)],
            muscleGroupsPerWeek: [.chest: 2],
            recovery: RecoveryMetrics(sessions: trainingDays, trainingDays: trainingDays, averageRPE: nil),
            analysisProfile: analysisProfile,
            sessionsInWindow: sessionsInWindow,
            sessionsInLastSevenDays: sessionsInLastSevenDays,
            effort: effort
        )
    }
}
