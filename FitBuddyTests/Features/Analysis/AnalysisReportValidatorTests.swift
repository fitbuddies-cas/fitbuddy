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
            lead: "Bench press can go up.",
            cards: [benchPress(from: 60, to: 62.5)],
            summary: "Bench press is ready."
        )

        let validated = AnalysisReportValidator.validate(report, against: evidence())

        XCTAssertEqual(validated.headline, "You're ready to progress.")
        XCTAssertEqual(validated.verdict, .progress)
        XCTAssertEqual(validated.lead, "Bench press can go up.")
        XCTAssertEqual(validated.summary, "Bench press is ready.")
    }

    /// #170: thin data gets no cards, and that is a valid report — nothing is
    /// inserted when no recovery is due.
    func testAReportWithoutCardsStaysValidAndEmpty() {
        let report = AnalysisReport(
            headline: "Hold steady.",
            verdict: .hold,
            lead: "Too little data for a change yet.",
            cards: [],
            summary: "Two sessions are too few to judge a trend."
        )

        let validated = AnalysisReportValidator.validate(report, against: evidence())

        XCTAssertEqual(validated, ValidatedAnalysisReport(
            headline: "Hold steady.",
            verdict: .hold,
            lead: "Too little data for a change yet.",
            cards: [],
            summary: "Two sessions are too few to judge a trend."
        ))
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

    /// The step is capped like prompt rule 6: a barbell step of 2.5 kg where
    /// the line lists no smaller step — no share of the working weight on top.
    func testLoadIncreaseIsCappedAtTheAllowedStep() {
        XCTAssertEqual(validate([benchPress(from: 60, to: 62.5)]).cards.first?.kind, .progression)
        XCTAssertEqual(validate([benchPress(from: 60, to: 66)]).cards, [.note(title: "Bench Press", text: "Clean overload.")])
        XCTAssertEqual(validate([benchPress(from: 60, to: 100)]).cards, [.note(title: "Bench Press", text: "Clean overload.")])
    }

    /// A dumbbell line listing a 2 kg step allows that step, and no more than
    /// the 2.5 kg floor beyond it: 10 → 12 kg is kept, 10 → 14 kg is not.
    func testListedStepCapsADumbbellIncrease() {
        let evidence = evidence(exercises: [
            ListedExercise(
                title: "Lateral Raise",
                muscleGroup: .shoulders,
                workingSet: WorkingSet(weightKg: 10, reps: 12),
                smallestStepKg: 2
            ),
        ])

        XCTAssertEqual(
            validate([
                .progression(exercise: "Lateral Raise", muscleGroup: "Shoulders", fromKg: 10, toKg: 12, reasoning: "Reps held."),
            ], evidence: evidence).cards.first?.kind,
            .progression
        )
        XCTAssertEqual(
            validate([
                .progression(exercise: "Lateral Raise", muscleGroup: "Shoulders", fromKg: 10, toKg: 14, reasoning: "Reps held."),
            ], evidence: evidence).cards,
            [.note(title: "Lateral Raise", text: "Reps held.")]
        )
    }

    /// A line without a listed step still allows one barbell step; the floor
    /// is shared with the prompt.
    func testWithoutAListedStepTheFloorIsTheBarbellStep() {
        let evidence = evidence(exercises: [
            ListedExercise(title: "Lateral Raise", muscleGroup: .shoulders, workingSet: WorkingSet(weightKg: 8, reps: 12)),
        ])

        XCTAssertEqual(AnalysisReportValidator.minimumStepKg, AnalysisPromptBuilder.minimumStepKg)
        XCTAssertEqual(
            validate([
                .progression(exercise: "Lateral Raise", muscleGroup: "Shoulders", fromKg: 8, toKg: 10.5, reasoning: "Reps held."),
            ], evidence: evidence).cards.first?.kind,
            .progression
        )
        XCTAssertEqual(
            validate([
                .progression(exercise: "Lateral Raise", muscleGroup: "Shoulders", fromKg: 8, toKg: 11, reasoning: "Reps held."),
            ], evidence: evidence).cards.first?.kind,
            .note
        )
    }

    /// A card that passes every check but says nothing is dropped, not shown
    /// with an empty sentence.
    func testValidProgressionWithoutReasoningIsDropped() {
        let validated = validate([
            .progression(exercise: "Bench Press", muscleGroup: "Chest", fromKg: 60, toKg: 62.5, reasoning: "  "),
        ])

        XCTAssertEqual(validated.cards, [])
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

    func testImbalanceWithEqualFrequenciesBecomesANote() {
        let evidence = evidence(perWeek: [.chest: 2, .legs: 2])

        XCTAssertEqual(validate([chestVersusLegs(2, 2)], evidence: evidence).cards, [
            .note(title: "Recommendation", text: "Add a leg session."),
        ])
        XCTAssertEqual(validate([chestVersusLegs(0, 0)], evidence: self.evidence(perWeek: [:])).cards.first?.kind, .note)
    }

    func testImbalanceWithOtherGroupBecomesANote() {
        let evidence = evidence(perWeek: [.chest: 3, .other: 1])
        let validated = validate([
            .imbalance(groupA: "Chest", perWeekA: 3, groupB: "Other", perWeekB: 1, reasoning: "Add cardio."),
        ], evidence: evidence)

        XCTAssertEqual(validated.cards, [.note(title: "Recommendation", text: "Add cardio.")])
    }

    func testValidImbalanceWithoutReasoningIsDropped() {
        let validated = validate([
            .imbalance(groupA: "Chest", perWeekA: 3, groupB: "Legs", perWeekB: 1, reasoning: ""),
        ])

        XCTAssertEqual(validated.cards, [])
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

    /// Below the threshold the model's reasoning alone does not make a
    /// recovery card: the schema forces a reasoning onto every card.
    func testRecoveryCardBelowTheThresholdBecomesANote() {
        let validated = validate(
            [.recovery(reasoning: "RPE 9.5 on every set this week.", suggestedRestHours: 72)],
            evidence: evidence(recovery: RecoveryMetrics(sessions: 3, trainingDays: 3, averageRPE: nil))
        )

        XCTAssertEqual(validated.cards, [.note(title: "Recovery", text: "RPE 9.5 on every set this week.")])
    }

    /// After a break, a recovery card would read "0 sessions / 7 days".
    func testRecoveryCardAfterABreakBecomesANote() {
        let validated = validate(
            [.recovery(reasoning: "Ease back in.", suggestedRestHours: 48)],
            evidence: evidence(recovery: RecoveryMetrics(sessions: 0, trainingDays: 0, averageRPE: nil))
        )

        XCTAssertEqual(validated.cards, [.note(title: "Recovery", text: "Ease back in.")])
    }

    func testRecoveryCardWithoutReasoningBelowTheThresholdIsDropped() {
        let validated = validate(
            [.recovery(reasoning: "  ", suggestedRestHours: 48)],
            evidence: evidence(recovery: RecoveryMetrics(sessions: 3, trainingDays: 3, averageRPE: nil))
        )

        XCTAssertEqual(validated.cards, [])
    }

    func testRecoveryCardWithoutReasoningAtTheThresholdGetsTheAppReasoning() {
        let metrics = RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil)
        let validated = validate([.recovery(reasoning: " ", suggestedRestHours: 48)], evidence: evidence(recovery: metrics))

        XCTAssertEqual(validated.cards, [
            .recovery(reasoning: AnalysisReportValidator.insertedRecoveryReasoning, metrics: metrics),
        ])
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

    func testRecoveryTurnsTheVerdictAndHeadline() {
        let validated = validate(
            [benchPress(from: 60, to: 62.5)],
            evidence: evidence(recovery: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil))
        )

        XCTAssertEqual(validated.verdict, .recover)
        XCTAssertEqual(validated.headline, "Recover this week.")
        XCTAssertEqual(
            validated.lead,
            "You trained on 6 of the last 7 days. Take the suggested rest before adding load.",
            "An overruled verdict gets the app's lead, not the model's"
        )
        XCTAssertEqual(validated.summary, "Summary")
    }

    func testModelRecoverVerdictKeepsItsHeadline() {
        let report = AnalysisReport(headline: "Take a break.", verdict: .recover, lead: "Rest first.", cards: [], summary: "Rest.")
        let validated = AnalysisReportValidator.validate(
            report,
            against: evidence(recovery: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil))
        )

        XCTAssertEqual(validated.verdict, .recover)
        XCTAssertEqual(validated.headline, "Take a break.")
        XCTAssertEqual(validated.lead, "Rest first.", "No override, so the model's lead stays")
    }

    func testVerdictIsKeptBelowTheThreshold() {
        let validated = validate([benchPress(from: 60, to: 62.5)])

        XCTAssertEqual(validated.verdict, .progress)
        XCTAssertEqual(validated.headline, "Headline")
        XCTAssertEqual(validated.lead, "Lead")
    }

    /// Every progression failed: the headline must not promise one (#177).
    func testProgressWithoutASurvivingProgressionBecomesHold() {
        let validated = validate([benchPress(from: 99, to: 100), chestVersusLegs(3, 1)])

        XCTAssertEqual(validated.cards.map(\.kind), [.note, .imbalance])
        XCTAssertEqual(validated.verdict, .hold)
        XCTAssertEqual(validated.headline, AnalysisReportValidator.holdHeadline)
        XCTAssertEqual(validated.lead, AnalysisReportValidator.holdLead, "The model's progress lead goes with its verdict")
    }

    func testProgressWithASurvivingProgressionStaysProgress() {
        let validated = validate([benchPress(from: 99, to: 100), benchPress(from: 60, to: 62.5)])

        XCTAssertEqual(validated.verdict, .progress)
        XCTAssertEqual(validated.lead, "Lead")
    }

    /// Recovery wins over the hold downgrade, even without any progression.
    func testForcedRecoveryIsNotTurnedIntoHold() {
        let validated = validate(
            [chestVersusLegs(3, 1)],
            evidence: evidence(recovery: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil))
        )

        XCTAssertEqual(validated.verdict, .recover)
        XCTAssertEqual(
            validated.lead,
            AnalysisReportValidator.recoveryLead(trainingDays: 6),
            "The recovery lead, not the hold lead"
        )
    }

    /// A model hold verdict passes through, cards or not.
    func testModelHoldVerdictIsKept() {
        let report = AnalysisReport(headline: "Keep going.", verdict: .hold, lead: "Hold.", cards: [chestVersusLegs(3, 1)], summary: "Hold.")
        let validated = AnalysisReportValidator.validate(report, against: evidence())

        XCTAssertEqual(validated.verdict, .hold)
        XCTAssertEqual(validated.headline, "Keep going.")
        XCTAssertEqual(validated.lead, "Hold.")
    }

    // MARK: - Card count

    /// Four model cards plus the inserted recovery card: the last note goes.
    func testInsertedRecoveryCardDropsTheLastNoteBeyondFourCards() {
        let metrics = RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil)
        let validated = validate([
            .note(title: "A", text: "One."),
            benchPress(from: 60, to: 62.5),
            .note(title: "B", text: "Two."),
            chestVersusLegs(3, 1),
        ], evidence: evidence(recovery: metrics))

        XCTAssertEqual(validated.cards.count, 4)
        XCTAssertEqual(validated.cards.map(\.kind), [.recovery, .note, .progression, .imbalance])
        XCTAssertEqual(validated.cards[1], .note(title: "A", text: "One."))
    }

    /// Without notes to drop, the last card that is not the recovery hint goes.
    func testCapDropsTheLastNonRecoveryCardWhenNoNoteIsLeft() {
        let metrics = RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil)
        let squat = AnalysisCard.progression(exercise: "Squat", muscleGroup: "Legs", fromKg: 80, toKg: 82.5, reasoning: "Reps held.")
        let validated = validate(
            [benchPress(from: 60, to: 62.5), squat, chestVersusLegs(3, 1), squat],
            evidence: evidence(
                exercises: [
                    ListedExercise(title: "Bench Press", muscleGroup: .chest, workingSet: WorkingSet(weightKg: 60, reps: 5)),
                    ListedExercise(title: "Squat", muscleGroup: .legs, workingSet: WorkingSet(weightKg: 80, reps: 5)),
                ],
                recovery: metrics
            )
        )

        XCTAssertEqual(validated.cards.map(\.kind), [.recovery, .progression, .progression, .imbalance])
    }

    func testRecoveryCardIsNeverCutEvenAtTheEnd() {
        let metrics = RecoveryMetrics(sessions: 7, trainingDays: 7, averageRPE: nil)
        let validated = validate([
            benchPress(from: 60, to: 62.5),
            .note(title: "A", text: "One."),
            benchPress(from: 60, to: 62.5),
            benchPress(from: 60, to: 62.5),
            .recovery(reasoning: "Rest first.", suggestedRestHours: 24),
        ], evidence: evidence(recovery: metrics))

        XCTAssertEqual(validated.cards.map(\.kind), [.progression, .progression, .progression, .recovery])
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

    func testBlankModelNoteIsDropped() {
        XCTAssertEqual(validate([.note(title: "Empty", text: " \n")]).cards, [])
    }

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

    // MARK: - Lead and full analysis (#170)

    private func report(lead: String, summary: String) -> ValidatedAnalysisReport {
        ValidatedAnalysisReport(headline: "H", verdict: .hold, lead: lead, cards: [], summary: summary)
    }

    func testALeadWithTextIsShown() {
        XCTAssertTrue(report(lead: "Keep going.", summary: "More.").hasLead)
        XCTAssertFalse(report(lead: " \n ", summary: "More.").hasLead)
    }

    func testASummaryDistinctFromTheLeadIsAFullAnalysis() {
        XCTAssertTrue(report(lead: "Keep going.", summary: "Two sessions are too few. Keep going.").hasFullAnalysis)
        XCTAssertTrue(report(lead: "", summary: "Two sessions are too few.").hasFullAnalysis)
    }

    func testABlankSummaryIsNoFullAnalysis() {
        XCTAssertFalse(report(lead: "Keep going.", summary: "  ").hasFullAnalysis)
    }

    /// Whitespace, case and Markdown aside, a summary that repeats the lead
    /// adds nothing.
    func testASummaryThatRepeatsTheLeadIsNoFullAnalysis() {
        XCTAssertFalse(report(lead: "Keep your loads.", summary: " keep  your\nloads. ").hasFullAnalysis)
        XCTAssertFalse(report(lead: "Keep your loads.", summary: "**Keep your loads.**").hasFullAnalysis)
        XCTAssertFalse(report(lead: "Rest two days. Keep your loads.", summary: "Keep your loads.").hasFullAnalysis)
    }

    // MARK: - Helpers

    private func validate(_ cards: [AnalysisCard], evidence: AnalysisReportEvidence? = nil) -> ValidatedAnalysisReport {
        AnalysisReportValidator.validate(
            AnalysisReport(headline: "Headline", verdict: .progress, lead: "Lead", cards: cards, summary: "Summary"),
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
