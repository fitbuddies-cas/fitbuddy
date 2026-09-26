import XCTest
@testable import FitBuddy

/// `AnalysisReportValidator.validateLogged` (US-16 AC4, #228): every place the
/// app does not take the model's answer as sent is recorded — which part,
/// what was done, why, and the model's figure next to the app's — and an
/// answer that goes through untouched records nothing.
///
/// The default evidence is the one `AnalysisReportValidatorTests` uses: bench
/// press at 60 × 5 with the 2-for-2 rule met, three training days, and a rule
/// that lands on `hold` (`noNewBest`). The default model verdict is `hold`
/// too, so no verdict intervention muddies a card assertion.
final class AnalysisValidationLogCaptureTests: XCTestCase {
    // MARK: - Nothing rejected

    func testAnAnswerTakenAsSentLogsNothing() {
        let log = self.log([
            benchPress(from: 60, to: 62.5),
            .imbalance(groupA: "Chest", perWeekA: 3, groupB: "Legs", perWeekB: 1, reasoning: "Add legs."),
            .note(title: "Sleep", text: "Sleep more."),
        ])

        XCTAssertEqual(log.interventions, [])
        XCTAssertEqual(log.modelVerdict, .hold)
        XCTAssertEqual(log.appVerdict, .hold)
        XCTAssertEqual(log.verdictReason, .noNewBest)
        XCTAssertFalse(log.verdictOverridden)
        XCTAssertNil(log.provider, "The validator does not know who answered")
    }

    func testAReportWithoutCardsLogsNothing() {
        XCTAssertEqual(log([]).interventions, [])
    }

    /// The report half of `validateLogged` is exactly `validate`.
    func testTheLoggedReportIsTheValidatedOne() {
        let report = report([benchPress(from: 60, to: 66)], verdict: .progress)

        XCTAssertEqual(
            AnalysisReportValidator.validateLogged(report, against: evidence()).report,
            AnalysisReportValidator.validate(report, against: evidence())
        )
    }

    // MARK: - Load progression

    func testAnOvershootIsLoggedWithTheAllowedRange() {
        XCTAssertEqual(log([benchPress(from: 60, to: 70)]).interventions, [
            AnalysisIntervention(
                subject: .progression,
                action: .downgraded,
                reason: .aboveRange,
                figure: AnalysisInterventionFigure(proposed: 70, app: 60, allowed: 62.5...65, unit: .kilograms)
            ),
        ])
    }

    func testAStepUnderTheRangeAndOffTheStepAreLoggedApart() {
        XCTAssertEqual(log([benchPress(from: 60, to: 61)]).interventions.map(\.reason), [.belowRange])
        XCTAssertEqual(log([benchPress(from: 60, to: 64)]).interventions.map(\.reason), [.offStep])
    }

    func testAMisquotedStartingWeightIsLoggedAgainstTheListedOne() {
        XCTAssertEqual(log([benchPress(from: 55, to: 57.5)]).interventions, [
            AnalysisIntervention(
                subject: .progression,
                action: .downgraded,
                reason: .wrongStartingWeight,
                figure: AnalysisInterventionFigure(proposed: 55, app: 60, unit: .kilograms)
            ),
        ])
    }

    func testAnUnlistedExerciseHasNoFigureOfTheApps() {
        let card = AnalysisCard.progression(
            exercise: "Deadlift", muscleGroup: "Back", fromKg: 100, toKg: 105, reasoning: "Pull more."
        )

        XCTAssertEqual(log([card]).interventions, [
            AnalysisIntervention(
                subject: .progression,
                action: .downgraded,
                reason: .notListed,
                figure: AnalysisInterventionFigure(proposed: 105, unit: .kilograms)
            ),
        ])
    }

    func testAnUnmetTwoForTwoRuleIsLogged() {
        let evidence = evidence(exercises: [Self.benchPressListed(twoForTwo: .notMet)])

        XCTAssertEqual(log([benchPress(from: 60, to: 62.5)], evidence: evidence).interventions.map(\.reason), [
            .conditionNotMet,
        ])
    }

    func testACardWithoutReasoningIsLoggedAsDropped() {
        let card = AnalysisCard.progression(
            exercise: "Bench Press", muscleGroup: "Chest", fromKg: 60, toKg: 62.5, reasoning: "  "
        )

        XCTAssertEqual(log([card]).interventions, [
            AnalysisIntervention(subject: .progression, action: .dropped, reason: .blankText),
        ])
    }

    func testAStrengthCardUnderEnduranceIsLoggedAsOutsideTheProfile() {
        let log = log([benchPress(from: 60, to: 62.5)], evidence: evidence(analysisProfile: .endurance))

        XCTAssertEqual(log.interventions.first, AnalysisIntervention(
            subject: .progression, action: .downgraded, reason: .domainNotCovered
        ))
    }

    // MARK: - Rep progression

    func testTooManyRepsAreLoggedWithTheAllowedStep() {
        let card = AnalysisCard.repProgression(
            exercise: "Bench Press", muscleGroup: "Chest", weightKg: 60, fromReps: 5, toReps: 9, reasoning: "Reps."
        )

        XCTAssertEqual(log([card]).interventions, [
            AnalysisIntervention(
                subject: .repProgression,
                action: .downgraded,
                reason: .aboveRepStep,
                figure: AnalysisInterventionFigure(
                    proposed: 9,
                    app: 5,
                    allowed: 6...Double(5 + AnalysisReportValidator.maxRepStep),
                    unit: .repetitions
                )
            ),
        ])
    }

    func testMisquotedStartingRepsAreLoggedAgainstTheListedOnes() {
        let card = AnalysisCard.repProgression(
            exercise: "Bench Press", muscleGroup: "Chest", weightKg: 60, fromReps: 8, toReps: 9, reasoning: "Reps."
        )

        XCTAssertEqual(log([card]).interventions.first?.figure, AnalysisInterventionFigure(
            proposed: 8, app: 5, unit: .repetitions
        ))
        XCTAssertEqual(log([card]).interventions.first?.reason, .wrongStartingReps)
    }

    // MARK: - Recovery

    func testARecoveryCardWithoutNeedIsLogged() {
        let card = AnalysisCard.recovery(reasoning: "Rest.", suggestedRestHours: 48)

        XCTAssertEqual(log([card]).interventions, [
            AnalysisIntervention(subject: .recovery, action: .downgraded, reason: .recoveryNotNeeded),
        ])
    }

    func testAMissingRecoveryCardIsLoggedAsInserted() {
        let log = log([], verdict: .recover, evidence: evidence(trainingDays: 6))

        XCTAssertEqual(log.interventions, [
            AnalysisIntervention(subject: .recovery, action: .inserted, reason: .recoveryMissing),
        ])
        XCTAssertEqual(log.verdictReason, .restDays)
    }

    func testARecoveryCardWithoutReasoningIsLoggedAsCompleted() {
        let card = AnalysisCard.recovery(reasoning: "", suggestedRestHours: 48)

        XCTAssertEqual(log([card], verdict: .recover, evidence: evidence(trainingDays: 6)).interventions, [
            AnalysisIntervention(subject: .recovery, action: .replaced, reason: .blankText),
        ])
    }

    // MARK: - Imbalance

    func testAMisquotedFrequencyIsLoggedAgainstTheApps() {
        let card = AnalysisCard.imbalance(groupA: "Chest", perWeekA: 2, groupB: "Legs", perWeekB: 1, reasoning: "Legs.")

        XCTAssertEqual(log([card]).interventions, [
            AnalysisIntervention(
                subject: .imbalance,
                action: .downgraded,
                reason: .frequencyMismatch,
                figure: AnalysisInterventionFigure(proposed: 2, app: 3, unit: .sessionsPerWeek)
            ),
        ])
    }

    func testImbalanceReasonsAreKeptApart() {
        let unknown = AnalysisCard.imbalance(groupA: "Chest", perWeekA: 3, groupB: "Cardio", perWeekB: 1, reasoning: "x")
        let even = AnalysisCard.imbalance(groupA: "Chest", perWeekA: 2, groupB: "Legs", perWeekB: 2, reasoning: "x")

        XCTAssertEqual(log([unknown]).interventions.map(\.reason), [.unknownMuscleGroup])
        XCTAssertEqual(
            log([even], evidence: evidence(perWeek: [.chest: 2, .legs: 2])).interventions.map(\.reason),
            [.noImbalance]
        )
    }

    // MARK: - Metric

    func testMetricReasonsAreKeptApart() {
        let enduranceWeek = evidence(weeklyMetrics: [.kilometers: 30])

        XCTAssertEqual(log([metric(from: 28, to: 32)], evidence: enduranceWeek).interventions, [
            AnalysisIntervention(
                subject: .metric,
                action: .downgraded,
                reason: .wrongStartingFigure,
                figure: AnalysisInterventionFigure(proposed: 28, app: 30, unit: .kilometers)
            ),
        ])
        let overshoot = log([metric(from: 30, to: 40)], evidence: enduranceWeek).interventions.first?.figure
        XCTAssertEqual(overshoot?.proposed, 40)
        XCTAssertEqual(overshoot?.app, 30)
        XCTAssertEqual(overshoot?.allowedMin ?? 0, 24, accuracy: 1e-9)
        XCTAssertEqual(overshoot?.allowedMax ?? 0, 36, accuracy: 1e-9)
        XCTAssertEqual(log([metric(from: 30, to: 40)], evidence: enduranceWeek).interventions.map(\.reason),
                       [.stepOutOfRange])
        XCTAssertEqual(log([metric(from: 30, to: 32)]).interventions.map(\.reason), [.noAppFigure])
        XCTAssertEqual(log([metric(from: 140, to: 135, unit: .beatsPerMinute)]).interventions.map(\.reason),
                       [.unitNotStatable])
        XCTAssertEqual(
            log([metric(from: 30, to: 32)], evidence: evidence(weeklyMetrics: [.kilometers: 30], analysisProfile: .strength))
                .interventions.first?.reason,
            .domainNotCovered
        )
    }

    // MARK: - Interference

    func testInterferenceReasonsAreKeptApart() {
        let card = AnalysisCard.interference(strengthDays: 4, cardioDays: 4, overlapDays: 3, reasoning: "Split them.")
        let noCardio = evidence(interference: InterferenceMetrics(strengthDays: 4, cardioDays: 0, overlapDays: 0))

        XCTAssertEqual(log([card], evidence: noCardio).interventions, [
            AnalysisIntervention(subject: .interference, action: .downgraded, reason: .noInterference),
        ])
        XCTAssertEqual(
            log([card], evidence: evidence(analysisProfile: .strength)).interventions.map(\.reason),
            [.domainNotCovered]
        )
    }

    // MARK: - Notes, cap, fourth class

    func testABlankNoteIsLoggedAsDropped() {
        XCTAssertEqual(log([.note(title: "Empty", text: " ")]).interventions, [
            AnalysisIntervention(subject: .note, action: .dropped, reason: .blankText),
        ])
    }

    func testCardsPastTheLimitAreLoggedAsDropped() {
        let notes = (1...6).map { AnalysisCard.note(title: "Note \($0)", text: "Text \($0)") }

        XCTAssertEqual(log(notes).interventions, [
            AnalysisIntervention(subject: .note, action: .dropped, reason: .overCardLimit),
            AnalysisIntervention(subject: .note, action: .dropped, reason: .overCardLimit),
        ])
    }

    /// ADR-014 §6: under `insufficientData` a valid progression is demoted to
    /// a note, and the log says so next to the verdict the app put over the
    /// model's.
    func testADemotionWithoutAVerdictIsLogged() {
        let log = log([benchPress(from: 60, to: 62.5)], verdict: .progress, evidence: evidence(sessionsInWindow: 3))

        XCTAssertEqual(log.appVerdict, .insufficientData)
        XCTAssertEqual(log.verdictReason, .tooFewSessions)
        XCTAssertEqual(log.interventions.first, AnalysisIntervention(
            subject: .progression, action: .downgraded, reason: .noVerdict
        ))
    }

    // MARK: - Verdict, headline, lead

    func testAnOverriddenVerdictIsLoggedWithItsHeadlineAndLead() {
        let log = log([], verdict: .progress)

        XCTAssertTrue(log.verdictOverridden)
        XCTAssertEqual(log.modelVerdict, .progress)
        XCTAssertEqual(log.appVerdict, .hold)
        XCTAssertEqual(log.interventions, [
            AnalysisIntervention(subject: .verdict, action: .replaced, reason: .verdictOverridden),
            AnalysisIntervention(subject: .headline, action: .replaced, reason: .verdictOverridden),
            AnalysisIntervention(subject: .lead, action: .replaced, reason: .verdictOverridden),
        ])
    }

    /// The model agrees on `progress`, but the card that backed its lead was
    /// struck: only the lead is replaced, and logged for that reason.
    func testAProgressLeadWithoutABackingCardIsLogged() {
        let evidence = evidence(exercises: [Self.benchPressListed(latestIsWindowBest: true)])

        let log = log([benchPress(from: 60, to: 70)], verdict: .progress, evidence: evidence)

        XCTAssertFalse(log.verdictOverridden)
        XCTAssertEqual(log.interventions.map(\.reason), [.aboveRange, .noBackingCard])
        XCTAssertEqual(log.interventions.last?.subject, .lead)
    }

    // MARK: - Helpers

    private func report(_ cards: [AnalysisCard], verdict: AnalysisVerdict = .hold) -> AnalysisReport {
        AnalysisReport(headline: "Headline", verdict: verdict, lead: "Lead", cards: cards, summary: "Summary")
    }

    private func log(
        _ cards: [AnalysisCard],
        verdict: AnalysisVerdict = .hold,
        evidence: AnalysisReportEvidence? = nil
    ) -> AnalysisValidationLog {
        AnalysisReportValidator.validateLogged(
            report(cards, verdict: verdict),
            against: evidence ?? self.evidence()
        ).log
    }

    private func benchPress(from: Double, to: Double) -> AnalysisCard {
        .progression(exercise: "Bench Press", muscleGroup: "Chest", fromKg: from, toKg: to, reasoning: "Clean overload.")
    }

    private func metric(from: Double, to: Double, unit: MetricUnit = .kilometers) -> AnalysisCard {
        .metric(label: "Weekly distance", from: from, to: to, unit: unit, reasoning: "Held.", source: "Run")
    }

    /// Bench press at 60 × 5, decidable, no plateau — ADR-014 lands on `hold`
    /// unless the latest session is the window's best.
    private static func benchPressListed(
        twoForTwo: TwoForTwoCondition = .met,
        latestIsWindowBest: Bool = false
    ) -> ListedExercise {
        ListedExercise(
            title: "Bench Press",
            muscleGroup: .chest,
            workingSet: WorkingSet(weightKg: 60, reps: 5),
            smallestStepKg: 2.5,
            twoForTwo: twoForTwo,
            progressionPoints: 5,
            isPlateaued: false,
            latestIsWindowBest: latestIsWindowBest
        )
    }

    private func evidence(
        exercises: [ListedExercise] = [benchPressListed()],
        perWeek: [MuscleGroup: Double] = [.chest: 3, .legs: 1],
        trainingDays: Int = 3,
        interference: InterferenceMetrics = InterferenceMetrics(strengthDays: 4, cardioDays: 4, overlapDays: 3),
        weeklyMetrics: [MetricUnit: Double] = [:],
        analysisProfile: AnalysisProfile = .overallLoad,
        sessionsInWindow: Int = 12
    ) -> AnalysisReportEvidence {
        AnalysisReportEvidence(
            exercises: exercises,
            muscleGroupsPerWeek: perWeek,
            recovery: RecoveryMetrics(sessions: trainingDays, trainingDays: trainingDays, averageRPE: nil),
            analysisProfile: analysisProfile,
            recoveryCountsUnanalysedTraining: false,
            interference: interference,
            weeklyMetrics: weeklyMetrics,
            sessionsInWindow: sessionsInWindow,
            sessionsInLastSevenDays: 3
        )
    }
}
