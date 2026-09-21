import XCTest
@testable import FitBuddy

/// `AnalysisVerdictRule` (#227): the decision tree of ADR-013, stage by stage
/// and at every threshold it names.
///
/// Every number asserted here is the ADR's, not a value read back out of the
/// implementation: 6 of 7 training days, 4 sessions in the window, 4
/// progression points, "more than half".
final class AnalysisVerdictRuleTests: XCTestCase {
    // MARK: - Stage 0 · rest gate

    func testSixTrainingDaysGiveRecover() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(trainingDays: 6))

        XCTAssertEqual(outcome, .init(verdict: .recover, reason: .restDays))
    }

    func testFiveTrainingDaysDoNotGiveRecover() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(trainingDays: 5))

        XCTAssertNotEqual(outcome.verdict, .recover)
    }

    /// The rest gate is first: it answers even where no later stage could.
    func testTheRestGateWinsOverAnEmptyDataBasis() {
        let outcome = AnalysisVerdictRule.outcome(
            for: evidence(trainingDays: 7, sessionsInWindow: 0, sessionsInLastSevenDays: 0, exercises: [])
        )

        XCTAssertEqual(outcome, .init(verdict: .recover, reason: .restDays))
    }

    /// It can force `recover`, never allow `progress` — so a week under the
    /// threshold falls through to the stages below rather than being cleared.
    func testTheRestGateNeverProducesProgressOnItsOwn() {
        let outcome = AnalysisVerdictRule.outcome(
            for: evidence(trainingDays: 1, exercises: [exercise(points: 5, latestIsWindowBest: false)])
        )

        XCTAssertEqual(outcome, .init(verdict: .hold, reason: .noNewBest))
    }

    // MARK: - Stage 1 · data gate

    func testThreeSessionsInTheWindowAreTooFew() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(sessionsInWindow: 3))

        XCTAssertEqual(outcome, .init(verdict: .insufficientData, reason: .tooFewSessions))
    }

    func testFourSessionsInTheWindowPassTheGate() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(sessionsInWindow: 4))

        XCTAssertNotEqual(outcome.reason, .tooFewSessions)
    }

    func testTheThresholdIsTheOneTheADRNames() {
        XCTAssertEqual(AnalysisVerdictRule.minimumSessionsInWindow, 4)
    }

    /// A window that widened until it found training can end in a break; the
    /// figures then describe the break.
    func testNoSessionInTheLastSevenDaysIsNotEnough() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(sessionsInLastSevenDays: 0))

        XCTAssertEqual(outcome, .init(verdict: .insufficientData, reason: .noRecentSession))
    }

    func testOneSessionInTheLastSevenDaysPassesTheGate() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(sessionsInLastSevenDays: 1))

        XCTAssertNotEqual(outcome.reason, .noRecentSession)
    }

    /// The window count is checked before the recency count, so the note names
    /// the first condition that fired.
    func testTooFewSessionsIsReportedBeforeRecency() {
        let outcome = AnalysisVerdictRule.outcome(
            for: evidence(sessionsInWindow: 1, sessionsInLastSevenDays: 0)
        )

        XCTAssertEqual(outcome.reason, .tooFewSessions)
    }

    // MARK: - Per profile (ADR-013 §5)

    /// Stages 2–4 are statements about an estimated 1RM, which endurance has
    /// none of. They are absent, not zero — so the rule says it has no
    /// verdict instead of falling through to `hold`.
    func testEnduranceCannotReachAPlateauStage() {
        let outcome = AnalysisVerdictRule.outcome(
            for: evidence(analysisProfile: .endurance, exercises: [])
        )

        XCTAssertEqual(outcome, .init(verdict: .insufficientData, reason: .noStrengthDomain))
    }

    /// The known negative consequence the ADR accepts: a pure runner never
    /// sees "You're ready to progress." in v0.
    func testEnduranceCanOnlyRecoverOrHaveNoVerdictInV0() {
        let verdicts = [
            AnalysisVerdictRule.outcome(for: evidence(analysisProfile: .endurance, trainingDays: 6)).verdict,
            AnalysisVerdictRule.outcome(for: evidence(analysisProfile: .endurance)).verdict,
            AnalysisVerdictRule.outcome(for: evidence(analysisProfile: .endurance, sessionsInWindow: 2)).verdict,
        ]

        XCTAssertEqual(verdicts, [.recover, .insufficientData, .insufficientData])
    }

    func testOverallLoadJudgesOnTheStrengthHalf() {
        let outcome = AnalysisVerdictRule.outcome(
            for: evidence(
                analysisProfile: .overallLoad,
                exercises: [exercise(points: 5, latestIsWindowBest: true)]
            )
        )

        XCTAssertEqual(outcome, .init(verdict: .progress, reason: .latestIsWindowBest))
    }

    // MARK: - Stage 2 · is a plateau decidable

    func testThreeProgressionPointsCannotDecideAPlateau() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(exercises: [exercise(points: 3)]))

        XCTAssertEqual(outcome, .init(verdict: .insufficientData, reason: .plateauUndecidable))
    }

    func testFourProgressionPointsCanDecideAPlateau() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(exercises: [exercise(points: 4)]))

        XCTAssertNotEqual(outcome.reason, .plateauUndecidable)
    }

    /// The same four points `ExerciseProgression.isPlateaued` needs — one
    /// plateau definition in the product (US-9 AC2).
    func testTheDecidableThresholdIsThePlateauDefinition() {
        XCTAssertEqual(ExerciseProgression.plateauSessionCount + 1, 4)
    }

    func testAWindowWithNoListedExerciseCannotDecideAPlateau() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(exercises: []))

        XCTAssertEqual(outcome, .init(verdict: .insufficientData, reason: .plateauUndecidable))
    }

    // MARK: - Stage 3 · plateau majority

    func testTwoOfThreePlateauedExercisesHold() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(exercises: [
            exercise(points: 5, isPlateaued: true),
            exercise(points: 5, isPlateaued: true),
            exercise(points: 5, latestIsWindowBest: true),
        ]))

        XCTAssertEqual(outcome, .init(verdict: .hold, reason: .plateauMajority))
    }

    /// "More than half", so an even split is not a majority and the stages
    /// below still get their turn.
    func testAnEvenSplitIsNotAMajority() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(exercises: [
            exercise(points: 5, isPlateaued: true),
            exercise(points: 5, latestIsWindowBest: true),
        ]))

        XCTAssertEqual(outcome, .init(verdict: .progress, reason: .latestIsWindowBest))
    }

    /// An exercise the app cannot judge does not count towards the half it
    /// would otherwise tip.
    func testUndecidableExercisesAreNotCountedInTheMajority() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(exercises: [
            exercise(points: 5, isPlateaued: true),
            exercise(points: 2),
            exercise(points: 2),
        ]))

        XCTAssertEqual(outcome, .init(verdict: .hold, reason: .plateauMajority))
    }

    // MARK: - Stage 4 · the latest session is the window's best

    func testANewBestInTheLatestSessionGivesProgress() {
        let outcome = AnalysisVerdictRule.outcome(
            for: evidence(exercises: [exercise(points: 4, latestIsWindowBest: true)])
        )

        XCTAssertEqual(outcome, .init(verdict: .progress, reason: .latestIsWindowBest))
    }

    /// The exercise has to be decidable: four points is where the statement
    /// starts to mean anything.
    func testANewBestOnAnUndecidableExerciseDoesNotGiveProgress() {
        let outcome = AnalysisVerdictRule.outcome(
            for: evidence(exercises: [exercise(points: 3, latestIsWindowBest: true)])
        )

        XCTAssertEqual(outcome, .init(verdict: .insufficientData, reason: .plateauUndecidable))
    }

    /// A plateaued movement cannot carry the step, even where its last session
    /// tied the window's best.
    func testAPlateauedExerciseDoesNotCarryTheStep() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(exercises: [
            exercise(points: 5, isPlateaued: false),
            exercise(points: 5, isPlateaued: false),
            exercise(points: 5, isPlateaued: true),
            exercise(points: 5, isPlateaued: true, latestIsWindowBest: true),
        ]))

        XCTAssertEqual(outcome, .init(verdict: .hold, reason: .noNewBest))
    }

    func testOneExerciseIsEnoughToCarryTheStep() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(exercises: [
            exercise(points: 5),
            exercise(points: 5),
            exercise(points: 5, latestIsWindowBest: true),
        ]))

        XCTAssertEqual(outcome, .init(verdict: .progress, reason: .latestIsWindowBest))
    }

    // MARK: - The rest

    func testDecidableWithoutAPlateauAndWithoutANewBestHolds() {
        let outcome = AnalysisVerdictRule.outcome(for: evidence(exercises: [exercise(points: 6)]))

        XCTAssertEqual(outcome, .init(verdict: .hold, reason: .noNewBest))
    }

    // MARK: - No substitute for missing effort (US-16 AC6, ADR-013 §4)

    /// Missing effort data is not a reason for `insufficientData`, and no
    /// stand-in value is put in its place: the e1RM stages decide on their
    /// own. Held by a test so nobody adds a default RPE later.
    func testAWeekWithoutAnyRPEStillDecides() {
        let withoutRPE = evidence(
            recovery: RecoveryMetrics(sessions: 4, trainingDays: 4, averageRPE: nil),
            exercises: [exercise(points: 5, latestIsWindowBest: true)]
        )
        let withRPE = evidence(
            recovery: RecoveryMetrics(sessions: 4, trainingDays: 4, averageRPE: 8),
            exercises: [exercise(points: 5, latestIsWindowBest: true)]
        )

        XCTAssertEqual(AnalysisVerdictRule.outcome(for: withoutRPE).verdict, .progress)
        XCTAssertEqual(AnalysisVerdictRule.outcome(for: withRPE), AnalysisVerdictRule.outcome(for: withoutRPE))
    }

    // MARK: - Reproducibility (US-16 AC1)

    /// The same evidence always yields the same verdict — the rule reads
    /// nothing but its argument.
    func testTheSameEvidenceAlwaysYieldsTheSameVerdict() {
        let evidence = self.evidence(exercises: [
            exercise(points: 5, isPlateaued: true),
            exercise(points: 5, latestIsWindowBest: true),
            exercise(points: 3),
        ])

        let outcomes = (0..<5).map { _ in AnalysisVerdictRule.outcome(for: evidence) }

        XCTAssertEqual(Set(outcomes.map(\.verdict)).count, 1)
    }

    // MARK: - Fixtures

    private func exercise(
        points: Int,
        isPlateaued: Bool = false,
        latestIsWindowBest: Bool = false
    ) -> ListedExercise {
        ListedExercise(
            title: "Bench Press \(points)-\(isPlateaued)-\(latestIsWindowBest)",
            muscleGroup: .chest,
            workingSet: WorkingSet(weightKg: 60, reps: 5),
            smallestStepKg: 2.5,
            progressionPoints: points,
            isPlateaued: isPlateaued,
            latestIsWindowBest: latestIsWindowBest
        )
    }

    /// Evidence that clears stages 0 and 1, so a test only has to state the
    /// stage it is about.
    private func evidence(
        analysisProfile: AnalysisProfile = .strength,
        trainingDays: Int = 3,
        recovery: RecoveryMetrics? = nil,
        sessionsInWindow: Int = 12,
        sessionsInLastSevenDays: Int = 3,
        exercises: [ListedExercise] = [ListedExercise(
            title: "Bench Press",
            muscleGroup: .chest,
            workingSet: WorkingSet(weightKg: 60, reps: 5),
            progressionPoints: 5
        )]
    ) -> AnalysisReportEvidence {
        AnalysisReportEvidence(
            exercises: exercises,
            muscleGroupsPerWeek: [.chest: 2],
            recovery: recovery
                ?? RecoveryMetrics(sessions: trainingDays, trainingDays: trainingDays, averageRPE: nil),
            analysisProfile: analysisProfile,
            sessionsInWindow: sessionsInWindow,
            sessionsInLastSevenDays: sessionsInLastSevenDays
        )
    }
}
