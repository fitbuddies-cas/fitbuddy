import XCTest
@testable import FitBuddy

/// `AnalysisReportValidator` (#175): which cards the cache backs, what the app
/// replaces in them, and what becomes of the ones it does not back.
final class AnalysisReportValidatorTests: XCTestCase {
    // MARK: - Progression

    func testValidProgressionCardIsKept() {
        let validated = validate([benchPress(from: 60, to: 62.5)])

        XCTAssertEqual(validated.cards, [
            .progression(exercise: "Bench Press", muscleGroup: .chest, fromKg: 60, toKg: 62.5, reasoning: "Clean overload."),
        ])
    }

    func testReportFieldsPassThroughUnchanged() {
        let report = AnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            cards: [benchPress(from: 60, to: 62.5)],
            summary: "Bench press is ready."
        )

        let validated = AnalysisReportValidator.validate(report, against: evidence())

        XCTAssertEqual(validated.headline, "You're ready to progress.")
        XCTAssertEqual(validated.verdict, .progress)
        XCTAssertEqual(validated.summary, "Bench press is ready.")
    }

    func testUnknownExerciseBecomesANote() {
        let validated = validate([
            .progression(exercise: "Incline Press", muscleGroup: "Chest", fromKg: 60, toKg: 62.5, reasoning: "Invented."),
        ])

        XCTAssertEqual(validated.cards, [.note(title: "Incline Press", text: "Invented.")])
    }

    func testWrongStartingWeightBecomesANote() {
        let validated = validate([benchPress(from: 65, to: 67.5)])

        XCTAssertEqual(validated.cards, [.note(title: "Bench Press", text: "Clean overload.")])
    }

    func testTargetNotAboveStartingWeightBecomesANote() {
        XCTAssertEqual(validate([benchPress(from: 60, to: 60)]).cards, [.note(title: "Bench Press", text: "Clean overload.")])
        XCTAssertEqual(validate([benchPress(from: 60, to: 57.5)]).cards, [.note(title: "Bench Press", text: "Clean overload.")])
    }

    func testExerciseNameMatchesIgnoringCaseAndWhitespace() {
        let validated = validate([
            .progression(exercise: "  bench PRESS \n", muscleGroup: "chest", fromKg: 60, toKg: 62.5, reasoning: "Clean overload."),
        ])

        XCTAssertEqual(validated.cards, [
            .progression(exercise: "Bench Press", muscleGroup: .chest, fromKg: 60, toKg: 62.5, reasoning: "Clean overload."),
        ])
    }

    /// Within ±0.5 kg the model only rounded — and the card shows the cache's
    /// figure, not the rounding.
    func testStartingWeightWithinToleranceIsReplacedByTheListedWeight() {
        let evidence = evidence(exercises: [
            ListedExercise(title: "Row (Dumbbell)", muscleGroup: .back, workingSet: WorkingSet(weightKg: 26.25, reps: 8)),
        ])
        let validated = validate([
            .progression(exercise: "Row (Dumbbell)", muscleGroup: "Back", fromKg: 26, toKg: 27.5, reasoning: "Reps held."),
        ], evidence: evidence)

        XCTAssertEqual(validated.cards, [
            .progression(exercise: "Row (Dumbbell)", muscleGroup: .back, fromKg: 26.25, toKg: 27.5, reasoning: "Reps held."),
        ])
    }

    func testToleranceBoundaryIsHalfAKilogram() {
        XCTAssertEqual(validate([benchPress(from: 60.5, to: 62.5)]).cards.first?.kind, .progression)
        XCTAssertEqual(validate([benchPress(from: 59.5, to: 62.5)]).cards.first?.kind, .progression)
        XCTAssertEqual(validate([benchPress(from: 60.6, to: 62.5)]).cards.first?.kind, .note)
        XCTAssertEqual(validate([benchPress(from: 59.4, to: 62.5)]).cards.first?.kind, .note)
    }

    /// The muscle group on the card is the app's classification, whatever the
    /// model wrote.
    func testMuscleGroupComesFromTheCache() {
        let validated = validate([
            .progression(exercise: "Bench Press", muscleGroup: "Shoulders", fromKg: 60, toKg: 62.5, reasoning: "Clean overload."),
        ])

        XCTAssertEqual(validated.cards, [
            .progression(exercise: "Bench Press", muscleGroup: .chest, fromKg: 60, toKg: 62.5, reasoning: "Clean overload."),
        ])
    }

    /// A listed bodyweight exercise has no working weight to start from.
    func testExerciseWithoutWorkingWeightBecomesANote() {
        let evidence = evidence(exercises: [ListedExercise(title: "Pull Up", muscleGroup: .back, workingSet: nil)])
        let validated = validate([
            .progression(exercise: "Pull Up", muscleGroup: "Back", fromKg: 0, toKg: 5, reasoning: "Add a belt."),
        ], evidence: evidence)

        XCTAssertEqual(validated.cards, [.note(title: "Pull Up", text: "Add a belt.")])
    }

    func testDuplicateTitleMatchesTheEntryWhoseWeightFits() {
        let evidence = evidence(exercises: [
            ListedExercise(title: "Curl", muscleGroup: .arms, workingSet: WorkingSet(weightKg: 12, reps: 10)),
            ListedExercise(title: "curl", muscleGroup: .arms, workingSet: WorkingSet(weightKg: 30, reps: 8)),
        ])
        let validated = validate([
            .progression(exercise: "Curl", muscleGroup: "Arms", fromKg: 30, toKg: 32.5, reasoning: "Reps held."),
        ], evidence: evidence)

        XCTAssertEqual(validated.cards, [
            .progression(exercise: "curl", muscleGroup: .arms, fromKg: 30, toKg: 32.5, reasoning: "Reps held."),
        ])
    }

    func testRejectedCardWithBlankNameGetsTheFallbackTitle() {
        let validated = validate([
            .progression(exercise: "  ", muscleGroup: "Chest", fromKg: 60, toKg: 62.5, reasoning: "Something."),
        ])

        XCTAssertEqual(validated.cards, [.note(title: "Recommendation", text: "Something.")])
    }

    /// A rejected card without reasoning would be an empty note.
    func testRejectedCardWithoutReasoningIsDropped() {
        let validated = validate([
            .progression(exercise: "Incline Press", muscleGroup: "Chest", fromKg: 60, toKg: 62.5, reasoning: " "),
        ])

        XCTAssertEqual(validated.cards, [])
    }

    // MARK: - Imbalance

    func testValidImbalanceCardIsKept() {
        let validated = validate([chestVersusLegs(3, 1)])

        XCTAssertEqual(validated.cards, [
            .imbalance(groupA: .chest, perWeekA: 3, groupB: .legs, perWeekB: 1, reasoning: "Add a leg session."),
        ])
    }

    func testImbalanceGroupsMatchIgnoringCaseAndWhitespace() {
        let validated = validate([
            .imbalance(groupA: " CHEST", perWeekA: 3, groupB: "legs ", perWeekB: 1, reasoning: "Add a leg session."),
        ])

        XCTAssertEqual(validated.cards.first?.kind, .imbalance)
    }

    func testImbalanceWithWrongFrequencyBecomesANote() {
        XCTAssertEqual(validate([chestVersusLegs(3, 2)]).cards, [.note(title: "Recommendation", text: "Add a leg session.")])
        XCTAssertEqual(validate([chestVersusLegs(2, 1)]).cards, [.note(title: "Recommendation", text: "Add a leg session.")])
    }

    func testImbalanceWithUnknownGroupBecomesANote() {
        let validated = validate([
            .imbalance(groupA: "Upper Body", perWeekA: 3, groupB: "Legs", perWeekB: 1, reasoning: "Add a leg session."),
        ])

        XCTAssertEqual(validated.cards, [.note(title: "Recommendation", text: "Add a leg session.")])
    }

    func testImbalanceOfAGroupWithItselfBecomesANote() {
        let validated = validate([
            .imbalance(groupA: "Chest", perWeekA: 3, groupB: "chest", perWeekB: 3, reasoning: "Odd."),
        ])

        XCTAssertEqual(validated.cards, [.note(title: "Recommendation", text: "Odd.")])
    }

    /// The prompt states one decimal, so a figure is compared at one decimal:
    /// 0.75 sessions per week is written `0.8`, and `0.8` matches.
    func testImbalanceFrequencyIsComparedAtOneDecimal() {
        let evidence = evidence(perWeek: [.chest: 2.3, .legs: 0.8])

        XCTAssertEqual(
            validate([chestVersusLegs(2.25, 0.75)], evidence: evidence).cards,
            [.imbalance(groupA: .chest, perWeekA: 2.3, groupB: .legs, perWeekB: 0.8, reasoning: "Add a leg session.")]
        )
        XCTAssertEqual(validate([chestVersusLegs(2.3, 0.7)], evidence: evidence).cards.first?.kind, .note)
    }

    func testUntrainedGroupCountsAsZero() {
        let evidence = evidence(perWeek: [.chest: 3])

        XCTAssertEqual(validate([chestVersusLegs(3, 0)], evidence: evidence).cards.first?.kind, .imbalance)
        XCTAssertEqual(validate([chestVersusLegs(3, 1)], evidence: evidence).cards.first?.kind, .note)
    }

    // MARK: - Recovery

    /// The acceptance criterion of #175: whatever the model put into
    /// `suggestedRestHours`, every figure on the card is the app's.
    func testRecoveryMetricsComeFromTheAppNotTheJSON() {
        let metrics = RecoveryMetrics(sessions: 7, trainingDays: 6, averageRPE: 8.2)
        let validated = validate(
            [.recovery(reasoning: "Six days in a row.", suggestedRestHours: 12)],
            evidence: evidence(recovery: metrics)
        )

        XCTAssertEqual(validated.cards, [.recovery(reasoning: "Six days in a row.", metrics: metrics)])
        XCTAssertEqual(metrics.suggestedRestHours, 48)
    }

    func testRecoveryCardWithReasoningIsKeptBelowTheThreshold() {
        let metrics = RecoveryMetrics(sessions: 3, trainingDays: 3, averageRPE: nil)
        let validated = validate(
            [.recovery(reasoning: "RPE 9.5 on every set this week.", suggestedRestHours: 72)],
            evidence: evidence(recovery: metrics)
        )

        XCTAssertEqual(validated.cards, [.recovery(reasoning: "RPE 9.5 on every set this week.", metrics: metrics)])
    }

    func testRecoveryCardWithoutReasoningBelowTheThresholdIsDropped() {
        let validated = validate(
            [.recovery(reasoning: "  ", suggestedRestHours: 48)],
            evidence: evidence(recovery: RecoveryMetrics(sessions: 3, trainingDays: 3, averageRPE: nil))
        )

        XCTAssertEqual(validated.cards, [])
    }

    func testRecoveryCardWithoutReasoningAtTheThresholdIsKept() {
        let metrics = RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil)
        let validated = validate([.recovery(reasoning: "", suggestedRestHours: 48)], evidence: evidence(recovery: metrics))

        XCTAssertEqual(validated.cards, [.recovery(reasoning: "", metrics: metrics)])
    }

    // MARK: - AC4: recovery hint at 6 of 7 days

    func testRecoveryCardIsInsertedFirstAtSixOfSevenDays() {
        let metrics = RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil)
        let validated = validate([benchPress(from: 60, to: 62.5)], evidence: evidence(recovery: metrics))

        XCTAssertEqual(validated.cards, [
            .recovery(reasoning: AnalysisReportValidator.insertedRecoveryReasoning, metrics: metrics),
            .progression(exercise: "Bench Press", muscleGroup: .chest, fromKg: 60, toKg: 62.5, reasoning: "Clean overload."),
        ])
    }

    func testNoRecoveryCardIsInsertedWhenTheModelSentOne() {
        let metrics = RecoveryMetrics(sessions: 7, trainingDays: 7, averageRPE: 8)
        let validated = validate(
            [benchPress(from: 60, to: 62.5), .recovery(reasoning: "Rest first.", suggestedRestHours: 24)],
            evidence: evidence(recovery: metrics)
        )

        XCTAssertEqual(validated.cards.filter { $0.kind == .recovery }.count, 1)
        XCTAssertEqual(validated.cards.last, .recovery(reasoning: "Rest first.", metrics: metrics))
    }

    func testNoRecoveryCardIsInsertedBelowTheThreshold() {
        let validated = validate(
            [benchPress(from: 60, to: 62.5)],
            evidence: evidence(recovery: RecoveryMetrics(sessions: 5, trainingDays: 5, averageRPE: nil))
        )

        XCTAssertFalse(validated.cards.contains { $0.kind == .recovery })
    }

    func testRecoveryCardIsInsertedIntoAReportWithoutCards() {
        let metrics = RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil)

        XCTAssertEqual(
            validate([], evidence: evidence(recovery: metrics)).cards,
            [.recovery(reasoning: AnalysisReportValidator.insertedRecoveryReasoning, metrics: metrics)]
        )
    }

    // MARK: - Note

    func testModelNotePassesThrough() {
        XCTAssertEqual(
            validate([.note(title: "Pull-ups", text: "Add one rep per set.")]).cards,
            [.note(title: "Pull-ups", text: "Add one rep per set.")]
        )
    }

    /// Card order survives validation; a downgrade keeps its place.
    func testCardOrderIsKept() {
        let validated = validate([
            .note(title: "First", text: "One."),
            benchPress(from: 99, to: 100),
            chestVersusLegs(3, 1),
        ])

        XCTAssertEqual(validated.cards.map(\.kind), [.note, .note, .imbalance])
    }

    // MARK: - Helpers

    private func validate(_ cards: [AnalysisCard], evidence: AnalysisReportEvidence? = nil) -> ValidatedAnalysisReport {
        AnalysisReportValidator.validate(
            AnalysisReport(headline: "Headline", verdict: .progress, cards: cards, summary: "Summary"),
            against: evidence ?? self.evidence()
        )
    }

    private func evidence(
        exercises: [ListedExercise] = [
            ListedExercise(title: "Bench Press", muscleGroup: .chest, workingSet: WorkingSet(weightKg: 60, reps: 5)),
        ],
        perWeek: [MuscleGroup: Double] = [.chest: 3, .legs: 1],
        recovery: RecoveryMetrics = RecoveryMetrics(sessions: 3, trainingDays: 3, averageRPE: nil)
    ) -> AnalysisReportEvidence {
        AnalysisReportEvidence(exercises: exercises, muscleGroupsPerWeek: perWeek, recovery: recovery)
    }

    private func benchPress(from: Double, to: Double) -> AnalysisCard {
        .progression(exercise: "Bench Press", muscleGroup: "Chest", fromKg: from, toKg: to, reasoning: "Clean overload.")
    }

    private func chestVersusLegs(_ chest: Double, _ legs: Double) -> AnalysisCard {
        .imbalance(groupA: "Chest", perWeekA: chest, groupB: "Legs", perWeekB: legs, reasoning: "Add a leg session.")
    }
}
