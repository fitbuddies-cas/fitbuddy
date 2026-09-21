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

    /// The fields the app does not touch. Headline, verdict and lead are no
    /// longer among them since #227 — the verdict is the app's, and the other
    /// two follow it where the two disagree. The evidence here is the one the
    /// model's own answer matches.
    func testReportFieldsPassThroughUnchanged() {
        let report = AnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            lead: "Bench press can go up.",
            cards: [benchPress(from: 60, to: 62.5)],
            summary: "Bench press is ready."
        )

        let validated = AnalysisReportValidator.validate(
            report,
            against: evidence(exercises: [Self.listedBenchPress(latestIsWindowBest: true)])
        )

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
            summary: "Two sessions are too few to judge a trend.",
            modelVerdict: .hold
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
            Self.listed(title: "Row (Dumbbell)", muscleGroup: .back, workingSet: WorkingSet(weightKg: 26.25, reps: 8), smallestStepKg: 1.25),
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

    /// The step is capped like prompt rule 6: the 2.5 kg step the line lists
    /// — no share of the working weight on top.
    func testLoadIncreaseIsCappedAtTheAllowedStep() {
        XCTAssertEqual(validate([benchPress(from: 60, to: 62.5)]).cards.first?.kind, .progression)
        XCTAssertEqual(validate([benchPress(from: 60, to: 66)]).cards, [.note(title: "Bench Press", text: "Clean overload.")])
        XCTAssertEqual(validate([benchPress(from: 60, to: 100)]).cards, [.note(title: "Bench Press", text: "Clean overload.")])
    }

    /// A barbell exercise ("(Barbell)" in the Hevy title) goes up in steps of
    /// 2.5 kg, even where its line lists a larger step.
    func testBarbellIncreaseIsCappedAtTwoAndAHalfKilograms() {
        let evidence = evidence(exercises: [
            Self.listed(
                title: "Bench Press (Barbell)",
                muscleGroup: .chest,
                workingSet: WorkingSet(weightKg: 60, reps: 5),
                smallestStepKg: 5
            ),
        ])

        XCTAssertEqual(
            validate([progression("Bench Press (Barbell)", from: 60, to: 62.5)], evidence: evidence).cards.first?.kind,
            .progression
        )
        XCTAssertEqual(
            validate([progression("Bench Press (Barbell)", from: 60, to: 65)], evidence: evidence).cards,
            [.note(title: "Bench Press (Barbell)", text: "Reps held.")]
        )
    }

    /// Any other exercise goes up by at most the step its line lists: a 2 kg
    /// dumbbell step allows 10 → 12 kg, not 10 → 12.5 kg.
    func testListedStepCapsANonBarbellIncrease() {
        let evidence = evidence(exercises: [
            Self.listed(
                title: "Lateral Raise",
                muscleGroup: .shoulders,
                workingSet: WorkingSet(weightKg: 10, reps: 12),
                smallestStepKg: 2
            ),
        ])

        XCTAssertEqual(
            validate([progression("Lateral Raise", from: 10, to: 12)], evidence: evidence).cards.first?.kind,
            .progression
        )
        XCTAssertEqual(
            validate([progression("Lateral Raise", from: 10, to: 12.5)], evidence: evidence).cards,
            [.note(title: "Lateral Raise", text: "Reps held.")]
        )
    }

    /// A non-barbell line without a listed step allows no heavier target:
    /// rule 6 progresses reps there.
    func testWithoutAListedStepANonBarbellIncreaseBecomesANote() {
        let evidence = evidence(exercises: [
            Self.listed(title: "Lateral Raise", muscleGroup: .shoulders, workingSet: WorkingSet(weightKg: 8, reps: 12)),
        ])

        XCTAssertEqual(
            validate([progression("Lateral Raise", from: 8, to: 10.5)], evidence: evidence).cards,
            [.note(title: "Lateral Raise", text: "Reps held.")]
        )
    }

    /// A machine logged at 40 and 45 kg: the 5 kg gap is past both 10 % and
    /// 2.5 kg, so the prompt lists no step, and 40 → 42.5 kg is not backed.
    func testMachineWithoutAListedStepBecomesANote() {
        let sessions = [45.0, 40.0].enumerated().map { offset, weight in
            ExerciseHistoryEntry(
                workoutID: "w-\(offset)",
                sessionStart: Date(timeIntervalSince1970: Double(offset) * 86_400),
                sets: [SetDetail(index: 0, type: .normal, weightKg: weight, reps: 12,
                                 distanceMeters: nil, durationSeconds: nil, rpe: nil)]
            )
        }
        let latest = WorkingSet(weightKg: 40, reps: 12)
        let step = AnalysisPromptBuilder.smallestStep(in: sessions, latest: latest)
        let evidence = evidence(exercises: [
            Self.listed(title: "Leg Extension (Machine)", muscleGroup: .legs, workingSet: latest, smallestStepKg: step),
        ])

        XCTAssertNil(step)
        XCTAssertEqual(
            validate([progression("Leg Extension (Machine)", from: 40, to: 42.5)], evidence: evidence).cards,
            [.note(title: "Leg Extension (Machine)", text: "Reps held.")]
        )
    }

    func testBarbellIsDetectedFromTheHevyTitleSuffix() {
        XCTAssertTrue(AnalysisPromptBuilder.isBarbell(title: "Bench Press (Barbell)"))
        XCTAssertTrue(AnalysisPromptBuilder.isBarbell(title: "squat (barbell)"))
        XCTAssertFalse(AnalysisPromptBuilder.isBarbell(title: "Bench Press (Dumbbell)"))
        XCTAssertFalse(AnalysisPromptBuilder.isBarbell(title: "Bench Press"))
        XCTAssertFalse(AnalysisPromptBuilder.isBarbell(title: "Leg Extension (Machine)"))
        XCTAssertEqual(AnalysisReportValidator.minimumStepKg, AnalysisPromptBuilder.minimumStepKg)
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
        let evidence = evidence(exercises: [Self.listed(title: "Pull Up", muscleGroup: .back, workingSet: nil)])
        let validated = validate([
            .progression(exercise: "Pull Up", muscleGroup: "Back", fromKg: 0, toKg: 5, reasoning: "Add a belt."),
        ], evidence: evidence)

        XCTAssertEqual(validated.cards, [.note(title: "Pull Up", text: "Add a belt.")])
    }

    func testDuplicateTitleMatchesTheEntryWhoseWeightFits() {
        let evidence = evidence(exercises: [
            Self.listed(title: "Curl", muscleGroup: .arms, workingSet: WorkingSet(weightKg: 12, reps: 10), smallestStepKg: 2.5),
            Self.listed(title: "curl", muscleGroup: .arms, workingSet: WorkingSet(weightKg: 30, reps: 8), smallestStepKg: 2.5),
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

    /// US-15 AC3 through the validator: the mixed week of four strength
    /// sessions and two runs on six days is 6 of 7 training days, so the hint
    /// is inserted and the progression is overruled exactly as a strength-only
    /// week's would be. The metrics carried into the card are the app's,
    /// heart rate included.
    func testAMixedWeekTriggersTheRecoveryHint() {
        let metrics = RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2, averageHeartRate: 148)
        let validated = validate([benchPress(from: 60, to: 62.5)], evidence: evidence(recovery: metrics))

        XCTAssertEqual(validated.cards.first, .recovery(
            reasoning: AnalysisReportValidator.insertedRecoveryReasoning,
            metrics: metrics
        ))
        XCTAssertEqual(validated.verdict, .recover)
        XCTAssertEqual(validated.lead, "You trained on 6 of the last 7 days. Take the suggested rest before your next hard session.")
    }

    /// A week of runs alone: before #184 it counted zero training days and no
    /// hint was possible. The lead names no domain, so it reads correctly here.
    func testAnEnduranceOnlyWeekTriggersTheRecoveryHint() {
        let metrics = RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil, averageHeartRate: 151)
        let validated = validate([], evidence: evidence(recovery: metrics))

        XCTAssertEqual(validated.cards, [
            .recovery(reasoning: AnalysisReportValidator.insertedRecoveryReasoning, metrics: metrics),
        ])
        XCTAssertEqual(validated.verdict, .recover)
        XCTAssertEqual(validated.headline, "Recover this week.")
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
            "You trained on 6 of the last 7 days. Take the suggested rest before your next hard session.",
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

    /// #227: the model no longer sets the verdict. Its answer says
    /// "progress", the app's own figures say "hold" — so the report says
    /// hold, and the model's own choice is kept for #228.
    func testTheAppsVerdictReplacesTheModels() {
        let validated = validate([benchPress(from: 60, to: 62.5)])

        XCTAssertEqual(validated.verdict, .hold)
        XCTAssertEqual(validated.modelVerdict, .progress)
        XCTAssertEqual(validated.headline, AnalysisReportValidator.holdHeadline)
        XCTAssertEqual(validated.lead, AnalysisReportValidator.holdLead)
    }

    /// Where the two agree, nothing is replaced: the model wrote its headline
    /// and lead for the verdict the app arrived at anyway.
    func testAnAgreeingModelKeepsItsWording() {
        let report = AnalysisReport(
            headline: "Keep the weights.", verdict: .hold, lead: "Hold.", cards: [], summary: "Summary"
        )

        let validated = AnalysisReportValidator.validate(report, against: evidence())

        XCTAssertEqual(validated.verdict, .hold)
        XCTAssertEqual(validated.headline, "Keep the weights.")
        XCTAssertEqual(validated.lead, "Hold.")
    }

    /// ADR-013 stage 4: the app's own figures carry the step, so the report
    /// progresses even though the model asked to hold — and the lead that
    /// argued for holding goes with the verdict it belonged to.
    func testTheAppsOwnFiguresCanProduceProgress() {
        let report = AnalysisReport(
            headline: "Keep the weights.", verdict: .hold, lead: "Hold.", cards: [], summary: "Summary"
        )

        let validated = AnalysisReportValidator.validate(
            report,
            against: evidence(exercises: [Self.listedBenchPress(latestIsWindowBest: true)])
        )

        XCTAssertEqual(validated.verdict, .progress)
        XCTAssertEqual(validated.headline, "You're ready to progress.")
        XCTAssertEqual(validated.lead, AnalysisReportValidator.progressLead)
        XCTAssertEqual(validated.modelVerdict, .hold)
    }

    /// A rejected card is still downgraded, but it no longer moves the
    /// verdict: #177 read "no card backs the step" as the verdict rule, and
    /// #227 replaced that with the app's own figures. Keeping both would let
    /// how well the model wrote a card decide the verdict again, which is
    /// exactly the swing US-16 AC1 is about.
    func testARejectedProgressionNoLongerDecidesTheVerdict() {
        let validated = validate(
            [benchPress(from: 99, to: 100), chestVersusLegs(3, 1)],
            evidence: evidence(exercises: [Self.listedBenchPress(latestIsWindowBest: true)])
        )

        XCTAssertEqual(validated.cards.map(\.kind), [.note, .imbalance])
        XCTAssertEqual(validated.verdict, .progress, "The app's figures carry the step, not the card")
    }

    /// A progression dropped for a blank reason is rejected just the same.
    func testADroppedProgressionNoLongerDecidesTheVerdict() {
        let blank = AnalysisCard.progression(
            exercise: "Bench Press", muscleGroup: "Chest", fromKg: 99, toKg: 100, reasoning: " "
        )
        let validated = validate(
            [blank, chestVersusLegs(3, 1)],
            evidence: evidence(exercises: [Self.listedBenchPress(latestIsWindowBest: true)])
        )

        XCTAssertEqual(validated.cards.map(\.kind), [.imbalance])
        XCTAssertEqual(validated.verdict, .progress)
    }

    /// The lead is replaced whenever the verdict was, whether or not the app
    /// took a card away: the model wrote it for the call the app just made
    /// differently (#170, ADR-013 §7). Before #227 it was kept where nothing
    /// had been downgraded.
    func testAnOverruledLeadIsReplacedEvenWithNothingDowngraded() {
        let validated = validate([.note(title: "Sleep", text: "Sleep more.")])

        XCTAssertEqual(validated.cards.map(\.kind), [.note])
        XCTAssertEqual(validated.verdict, .hold)
        XCTAssertEqual(validated.lead, AnalysisReportValidator.holdLead)
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

    /// A rejected progression under a forced recovery still gets the recovery
    /// lead, never the hold lead.
    func testForcedRecoveryWithARejectedProgressionKeepsTheRecoveryLead() {
        let validated = validate(
            [benchPress(from: 99, to: 100)],
            evidence: evidence(recovery: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil))
        )

        XCTAssertEqual(validated.verdict, .recover)
        XCTAssertEqual(validated.headline, AnalysisReportValidator.recoveryHeadline)
        XCTAssertEqual(validated.lead, AnalysisReportValidator.recoveryLead(trainingDays: 6))
    }

    /// A model hold verdict passes through where the app agrees, cards or not.
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
                    Self.listed(title: "Bench Press", muscleGroup: .chest, workingSet: WorkingSet(weightKg: 60, reps: 5), smallestStepKg: 2.5),
                    Self.listed(title: "Squat", muscleGroup: .legs, workingSet: WorkingSet(weightKg: 80, reps: 5), smallestStepKg: 2.5),
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

    // MARK: - Analysis profile (US-15 AC1, #185)

    /// ADR-013 §5, the consequence the ADR names and accepts: under
    /// "Endurance" stages 2 to 4 do not exist, because an estimated 1RM does
    /// not. A pure runner therefore never sees "You're ready to progress." in
    /// v0 — before #227 the model's own progress verdict stood here.
    func testAnEnduranceRunCannotProgressInV0() {
        let report = AnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            lead: "Your easy weeks are paying off — add a fourth run.",
            cards: [.note(title: "Volume", text: "Weekly distance rose for three weeks.")],
            summary: "Summary"
        )

        let validated = AnalysisReportValidator.validate(
            report,
            against: evidence(exercises: [], analysisProfile: .endurance)
        )

        XCTAssertEqual(validated.verdict, .insufficientData)
        XCTAssertEqual(validated.headline, AnalysisReportValidator.insufficientDataHeadline)
        XCTAssertEqual(validated.lead, AnalysisReportValidator.insufficientDataLead)
    }

    /// A strength run whose figures carry no step holds, whatever the model
    /// wrote and whatever its cards said.
    func testAStrengthRunWithoutANewBestHolds() {
        let report = AnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            lead: "Add load.",
            cards: [.note(title: "Volume", text: "Volume rose.")],
            summary: "Summary"
        )

        let validated = AnalysisReportValidator.validate(
            report,
            against: evidence(analysisProfile: .strength)
        )

        XCTAssertEqual(validated.verdict, .hold)
        XCTAssertEqual(validated.headline, AnalysisReportValidator.holdHeadline)
    }

    /// "Overall load" is judged on its strength half (ADR-013 §5) — the
    /// default, and what every build before #185 did.
    func testOverallLoadIsJudgedOnItsStrengthHalf() {
        let report = AnalysisReport(
            headline: "Hold steady this week.",
            verdict: .hold,
            lead: "Hold.",
            cards: [.note(title: "Volume", text: "Volume rose.")],
            summary: "Summary"
        )

        let validated = AnalysisReportValidator.validate(
            report,
            against: evidence(exercises: [Self.listedBenchPress(latestIsWindowBest: true)])
        )

        XCTAssertEqual(validated.verdict, .progress)
    }

    /// The card's figures span every session whatever the profile (one body,
    /// one recovery), so where the analysis left training out the reasoning
    /// says which count the user is looking at.
    func testTheInsertedRecoveryReasoningNamesTheTrainingItCounted() {
        let report = AnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            lead: "Add load.",
            cards: [],
            summary: "Summary"
        )

        let validated = AnalysisReportValidator.validate(
            report,
            against: evidence(
                recovery: RecoveryMetrics(sessions: 7, trainingDays: 6, averageRPE: nil),
                analysisProfile: .strength,
                countsUnanalysedTraining: true
            )
        )

        XCTAssertEqual(
            validated.cards.first,
            .recovery(
                reasoning: AnalysisReportValidator.insertedRecoveryReasoning(
                    countingUnanalysedTraining: true
                ),
                metrics: RecoveryMetrics(sessions: 7, trainingDays: 6, averageRPE: nil)
            )
        )
        XCTAssertTrue(
            AnalysisReportValidator
                .insertedRecoveryReasoning(countingUnanalysedTraining: true)
                .hasSuffix("including the training this analysis left out.")
        )
    }

    /// A Hevy-only window resolves to "Strength" and has left nothing out, so
    /// the sentence stays off — it would name training that does not exist.
    func testTheRecoveryReasoningIsUnchangedWhenNothingWasLeftOut() {
        XCTAssertEqual(
            AnalysisReportValidator.insertedRecoveryReasoning(countingUnanalysedTraining: false),
            AnalysisReportValidator.insertedRecoveryReasoning
        )
    }

    // MARK: - Metric cards (US-15 AC5/AC7, #186)

    /// The app is the authority for its own figures: the card keeps the
    /// model's target and its sentence, and states the week's own distance as
    /// the figure it starts from.
    func testAMetricCardTakesItsCurrentFigureFromTheApp() {
        let validated = AnalysisReportValidator.validate(
            metricCard(from: 32.4, to: 35),
            against: evidence(weeklyMetrics: [.kilometers: 32.4])
        )

        guard case let .metric(label, from, to, unit, _, source) = validated else {
            return XCTFail("expected a metric card, got \(String(describing: validated))")
        }
        XCTAssertEqual(label, "Weekly distance")
        XCTAssertEqual(from, 32.4)
        XCTAssertEqual(to, 35)
        XCTAssertEqual(unit, .kilometers)
        XCTAssertEqual(source, "Run")
    }

    /// `from` has to be the figure the prompt printed, not merely near it
    /// (#186 review). The 5 % tolerance it replaces allowed 620 kg of slack at
    /// a weekly volume of 12 400 kg, so the card and its own reasoning
    /// sentence could state different numbers.
    ///
    /// Replaces `testAFigureOutsideTheToleranceIsNotAMetricCard`.
    func testFromMustBeTheFigureThePromptPrinted() {
        // The prompt printed "32.4 km", so 32.4 is the figure — and 31 is not,
        // although it is within the old 5 %.
        let quoted = AnalysisReportValidator.validate(
            metricCard(from: 32.4, to: 35),
            against: evidence(weeklyMetrics: [.kilometers: 32.44])
        )
        let nearby = AnalysisReportValidator.validate(
            metricCard(from: 31, to: 35),
            against: evidence(weeklyMetrics: [.kilometers: 32.44])
        )

        XCTAssertEqual(quoted?.kind, .metric)
        XCTAssertEqual(nearby?.kind, .note)
    }

    /// The equality is at the precision the **prompt** printed the figure
    /// with, which for a volume is whole kilograms — the card shows two
    /// decimals, but the model was never shown them.
    func testAVolumeIsComparedAtWholeKilograms() {
        let validated = AnalysisReportValidator.validate(
            metricCard(from: 12_400, to: 13_000, unit: .kilograms, label: "Weekly volume"),
            against: evidence(weeklyMetrics: [.kilograms: 12_400.4], analysisProfile: .strength)
        )

        XCTAssertEqual(validated?.kind, .metric)
    }

    /// A unit the app has no figure for in the last seven days cannot be
    /// checked, so the card is not drawn as a measurement.
    func testAMetricCardWithoutAWeeklyFigureBecomesANote() {
        let validated = AnalysisReportValidator.validate(
            metricCard(from: 32, to: 35),
            against: evidence(weeklyMetrics: [:])
        )

        XCTAssertEqual(validated?.kind, .note)
    }

    /// A target a fifth past the week's own figure is a number, not a
    /// recommendation.
    func testATargetTooFarFromTheWeekIsNotAMetricCard() {
        let inside = AnalysisReportValidator.validate(
            metricCard(from: 32, to: 38),
            against: evidence(weeklyMetrics: [.kilometers: 32])
        )
        let outside = AnalysisReportValidator.validate(
            metricCard(from: 32, to: 64),
            against: evidence(weeklyMetrics: [.kilometers: 32])
        )

        XCTAssertEqual(inside?.kind, .metric)
        XCTAssertEqual(outside?.kind, .note)
    }

    /// A card recommending the figure the week already has recommends nothing,
    /// and its delta would read "+0 km" (AC7).
    func testAMetricCardWithoutAStepBecomesANote() {
        let validated = AnalysisReportValidator.validate(
            metricCard(from: 32, to: 32),
            against: evidence(weeklyMetrics: [.kilometers: 32])
        )

        XCTAssertEqual(validated?.kind, .note)
    }

    /// US-15 AC5: under "Endurance" a card measured in kilograms is not
    /// validated, so no kilogram reaches the screen.
    func testNoKilogramCardSurvivesTheEnduranceProfile() {
        let validated = AnalysisReportValidator.validate(
            metricCard(from: 12_000, to: 13_000, unit: .kilograms, label: "Weekly volume"),
            against: evidence(weeklyMetrics: [.kilograms: 12_000], analysisProfile: .endurance)
        )

        XCTAssertEqual(validated?.kind, .note)
    }

    /// The mirror image, and the reason the rule is on the unit rather than
    /// written out twice.
    func testNoKilometreCardSurvivesTheStrengthProfile() {
        let validated = AnalysisReportValidator.validate(
            metricCard(from: 32, to: 35),
            against: evidence(weeklyMetrics: [.kilometers: 32], analysisProfile: .strength)
        )

        XCTAssertEqual(validated?.kind, .note)
    }

    /// The blocker of #186's review. A metric card is a figure **and a target
    /// for it**, so a heart-rate card is a prescribed heart rate — which
    /// ground rule 7 forbids (US-3 AC3). The schema does not offer the unit;
    /// this is the second door, for a provider that ignored the schema. It is
    /// refused under every profile, even with the app's own anchor present and
    /// every other rule satisfied.
    ///
    /// Replaces `testAHeartRateCardPassesUnderEveryProfile`, which asserted
    /// exactly what the review reverses.
    func testNoHeartRateCardFromTheModelIsEverValidated() {
        for profile in AnalysisProfile.allCases {
            let validated = AnalysisReportValidator.validate(
                metricCard(from: 152, to: 148, unit: .beatsPerMinute, label: "Mean heart rate"),
                against: evidence(weeklyMetrics: [.beatsPerMinute: 152], analysisProfile: profile)
            )

            XCTAssertEqual(validated?.kind, .note, "\(profile)")
        }
    }

    /// A unit both domains record still passes under either profile — the rule
    /// is about the heart rate, not about domain-free units.
    func testADurationCardPassesUnderEveryProfile() {
        for profile in AnalysisProfile.allCases {
            let validated = AnalysisReportValidator.validate(
                metricCard(from: 6.5, to: 7, unit: .hours, label: "Weekly training time"),
                against: evidence(weeklyMetrics: [.hours: 6.5], analysisProfile: profile)
            )

            XCTAssertEqual(validated?.kind, .metric, "\(profile)")
        }
    }

    /// AC5 reaches the strength card as well: an endurance analysis shows no
    /// progression, whatever the model sent.
    func testNoProgressionCardSurvivesTheEnduranceProfile() {
        let validated = AnalysisReportValidator.validate(
            progression("Bench Press", from: 60, to: 62.5),
            against: evidence(analysisProfile: .endurance)
        )

        XCTAssertEqual(validated?.kind, .note)
    }

    /// A surviving metric card no longer lifts the verdict either. Before
    /// #227 a card asking for +3 km was what let an endurance report keep
    /// "progress"; ADR-013 removes that path and leaves such a run without a
    /// verdict until #241 gives it an effort figure.
    func testAMetricCardNoLongerBacksAProgressVerdict() {
        let report = AnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            lead: "Add about 3 km next week.",
            cards: [metricCard(from: 32, to: 35)],
            summary: "Summary"
        )

        let validated = AnalysisReportValidator.validate(
            report,
            against: evidence(
                exercises: [],
                weeklyMetrics: [.kilometers: 32],
                analysisProfile: .endurance
            )
        )

        XCTAssertEqual(validated.verdict, .insufficientData)
        XCTAssertEqual(
            validated.cards.map(\.kind),
            [.note, .note],
            "The app's note first, the metric card downgraded under it"
        )
    }

    /// The metric card itself is still validated against the app's figure —
    /// only its effect on the verdict is gone.
    func testAMetricCardIsStillCheckedAgainstTheAppsFigure() {
        let report = AnalysisReport(
            headline: "Hold steady this week.",
            verdict: .hold,
            lead: "Hold.",
            cards: [metricCard(from: 32, to: 35)],
            summary: "Summary"
        )

        let validated = AnalysisReportValidator.validate(
            report,
            against: evidence(weeklyMetrics: [.kilometers: 32], analysisProfile: .overallLoad)
        )

        XCTAssertEqual(validated.cards.map(\.kind), [.metric])
        XCTAssertEqual(validated.verdict, .hold)
    }

    // MARK: - Interference cards (US-15 AC2, #186)

    /// The three counts on the card are the app's, whatever the model wrote.
    func testAnInterferenceCardCarriesTheAppsDayCounts() {
        let interference = InterferenceMetrics(strengthDays: 4, cardioDays: 4, overlapDays: 3)

        let validated = AnalysisReportValidator.validate(
            .interference(strengthDays: 9, cardioDays: 1, overlapDays: 0, reasoning: "Move one run."),
            against: evidence(interference: interference)
        )

        guard case let .interference(metrics, reasoning) = validated else {
            return XCTFail("expected an interference card, got \(String(describing: validated))")
        }
        XCTAssertEqual(metrics, interference)
        XCTAssertEqual(reasoning, "Move one run.")
    }

    /// A week of one domain has no interference to write about.
    func testAnInterferenceCardOverASingleDomainWeekBecomesANote() {
        let validated = AnalysisReportValidator.validate(
            .interference(strengthDays: 4, cardioDays: 3, overlapDays: 2, reasoning: "Move one run."),
            against: evidence(interference: InterferenceMetrics(strengthDays: 5, cardioDays: 0, overlapDays: 0))
        )

        XCTAssertEqual(validated?.kind, .note)
    }

    /// Review finding 4: the card is a statement about both domains at once,
    /// so a single-domain profile has no card here — under "Strength" it would
    /// put four running days on a screen that says the running was left out,
    /// with no sentence to explain them.
    func testNoInterferenceCardSurvivesASingleDomainProfile() {
        for profile in [AnalysisProfile.strength, .endurance] {
            let validated = AnalysisReportValidator.validate(
                .interference(strengthDays: 4, cardioDays: 4, overlapDays: 3, reasoning: "Move one run."),
                against: evidence(
                    interference: InterferenceMetrics(strengthDays: 4, cardioDays: 4, overlapDays: 3),
                    analysisProfile: profile
                )
            )

            XCTAssertEqual(validated?.kind, .note, "\(profile)")
        }
    }

    /// Both domains in the week but never on the same day is a finding of its
    /// own, not a reason to drop the card.
    func testAWeekWithoutAnOverlapStillCarriesTheCard() {
        let validated = AnalysisReportValidator.validate(
            .interference(strengthDays: 3, cardioDays: 3, overlapDays: 0, reasoning: "Six days, no rest."),
            against: evidence(interference: InterferenceMetrics(strengthDays: 3, cardioDays: 3, overlapDays: 0))
        )

        XCTAssertEqual(validated?.kind, .interference)
    }

    // MARK: - The fourth verdict class (#227, ADR-013 §6)

    /// Headline and lead are the app's here, word for word from ADR-013 §6:
    /// the model's lead argues for a verdict the app has just withdrawn.
    func testAReportWithoutAVerdictGetsTheAppsHeadlineAndLead() {
        let validated = validate([], evidence: evidence(sessionsInWindow: 3))

        XCTAssertEqual(validated.verdict, .insufficientData)
        XCTAssertEqual(validated.headline, "Not enough data to judge.")
        XCTAssertEqual(
            validated.lead,
            "Your logged training doesn't yet support a recommendation for or against more load. "
                + "Keep training as before — the next analysis will have more to go on."
        )
    }

    /// One note, first, naming the condition that fired.
    func testTooFewSessionsAreNamedInTheNote() {
        let validated = validate([], evidence: evidence(sessionsInWindow: 3))

        XCTAssertEqual(validated.cards, [
            .note(
                title: "Why there's no verdict",
                text: "This analysis covers 3 of the 4 sessions the app needs before it reads a trend."
            ),
        ])
    }

    func testAWindowEndingInABreakIsNamedInTheNote() {
        let validated = validate([], evidence: evidence(sessionsInLastSevenDays: 0))

        XCTAssertEqual(validated.cards, [
            .note(
                title: "Why there's no verdict",
                text: "Nothing in the last 7 days belongs to this analysis, so its figures describe a break "
                    + "rather than a training week."
            ),
        ])
    }

    func testAnUndecidablePlateauIsNamedInTheNote() {
        let validated = validate([], evidence: evidence(exercises: [Self.listedBenchPress(progressionPoints: 3)]))

        XCTAssertEqual(validated.cards, [
            .note(
                title: "Why there's no verdict",
                text: "No exercise here has the 4 sessions the app needs before it can tell a plateau from progress."
            ),
        ])
    }

    func testTheMissingEnduranceFigureIsNamedInTheNote() {
        let validated = validate([], evidence: evidence(exercises: [], analysisProfile: .endurance))

        XCTAssertEqual(validated.cards, [
            .note(
                title: "Why there's no verdict",
                text: "Under Endurance the app has no estimated 1RM to read a trend from — "
                    + "that figure exists for strength only."
            ),
        ])
    }

    /// A progression card *is* a verdict, so it cannot stand under a report
    /// that has none — but its sentence still reaches the screen.
    func testAProgressionCardIsDowngradedWithoutAVerdict() {
        let validated = validate(
            [benchPress(from: 60, to: 62.5)],
            evidence: evidence(sessionsInWindow: 3)
        )

        XCTAssertEqual(validated.cards.map(\.kind), [.note, .note])
        XCTAssertEqual(validated.cards.last, .note(title: "Bench Press", text: "Clean overload."))
    }

    /// Imbalance and interference carry nothing but figures the app measured
    /// and replaced, so they stay (ADR-013 §6).
    func testMeasuredCardsSurviveWithoutAVerdict() {
        let validated = validate(
            [chestVersusLegs(3, 1), .interference(strengthDays: 4, cardioDays: 4, overlapDays: 3, reasoning: "Split them.")],
            evidence: evidence(sessionsInWindow: 3)
        )

        XCTAssertEqual(validated.cards.map(\.kind), [.note, .imbalance, .interference])
    }

    /// No stand-in for effort that was never logged: a week without any RPE
    /// still decides on the e1RM stages (ADR-013 §4, US-16 AC6).
    func testMissingEffortDataAloneIsNotAReasonToWithholdAVerdict() {
        let validated = validate(
            [benchPress(from: 60, to: 62.5)],
            evidence: evidence(
                exercises: [Self.listedBenchPress(latestIsWindowBest: true)],
                recovery: RecoveryMetrics(sessions: 4, trainingDays: 4, averageRPE: nil)
            )
        )

        XCTAssertEqual(validated.verdict, .progress)
        XCTAssertNil(validated.cards.first(where: { $0.kind == .note }))
    }

    /// The rest gate comes first, so a week of six training days gets
    /// "Recover this week." even where the data basis is otherwise too thin
    /// to judge.
    func testTheRestGateWinsOverAThinDataBasis() {
        let validated = validate(
            [],
            evidence: evidence(
                exercises: [],
                recovery: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil),
                sessionsInWindow: 1
            )
        )

        XCTAssertEqual(validated.verdict, .recover)
    }

    // MARK: - Fixtures for the new kinds

    private func metricCard(
        from: Double,
        to: Double,
        unit: MetricUnit = .kilometers,
        label: String = "Weekly distance"
    ) -> AnalysisCard {
        .metric(
            label: label,
            from: from,
            to: to,
            unit: unit,
            reasoning: "The figure held for three weeks.",
            source: "Run"
        )
    }

    /// A listed exercise as the card tests need it: decidable, not plateaued
    /// and without a new best in the latest session, so ADR-013 lands on
    /// `hold` and the cards stay what the assertion is about (#227).
    private static func listed(
        title: String,
        muscleGroup: MuscleGroup,
        workingSet: WorkingSet?,
        smallestStepKg: Double? = nil,
        progressionPoints: Int = 5,
        isPlateaued: Bool = false,
        latestIsWindowBest: Bool = false
    ) -> ListedExercise {
        ListedExercise(
            title: title,
            muscleGroup: muscleGroup,
            workingSet: workingSet,
            smallestStepKg: smallestStepKg,
            progressionPoints: progressionPoints,
            isPlateaued: isPlateaued,
            latestIsWindowBest: latestIsWindowBest
        )
    }

    /// The bench press line the default evidence lists.
    ///
    /// Since #227 it carries its plateau facts too, because the verdict is
    /// derived from them: five progression points, no plateau and no new best
    /// in the latest session, which is ADR-013's "Rest" row — `hold`. The
    /// card tests want a verdict that changes nothing about their cards, and
    /// that is this one.
    private static func listedBenchPress(
        progressionPoints: Int = 5,
        isPlateaued: Bool = false,
        latestIsWindowBest: Bool = false
    ) -> ListedExercise {
        Self.listed(
            title: "Bench Press",
            muscleGroup: .chest,
            workingSet: WorkingSet(weightKg: 60, reps: 5),
            smallestStepKg: 2.5,
            progressionPoints: progressionPoints,
            isPlateaued: isPlateaued,
            latestIsWindowBest: latestIsWindowBest
        )
    }

    private func evidence(
        exercises: [ListedExercise] = [listedBenchPress()],
        perWeek: [MuscleGroup: Double] = [.chest: 3, .legs: 1],
        recovery: RecoveryMetrics = RecoveryMetrics(sessions: 3, trainingDays: 3, averageRPE: nil),
        interference: InterferenceMetrics = InterferenceMetrics(strengthDays: 4, cardioDays: 4, overlapDays: 3),
        weeklyMetrics: [MetricUnit: Double] = [:],
        analysisProfile: AnalysisProfile = .overallLoad,
        countsUnanalysedTraining: Bool = false,
        sessionsInWindow: Int = 12,
        sessionsInLastSevenDays: Int = 3
    ) -> AnalysisReportEvidence {
        AnalysisReportEvidence(
            exercises: exercises,
            muscleGroupsPerWeek: perWeek,
            recovery: recovery,
            analysisProfile: analysisProfile,
            recoveryCountsUnanalysedTraining: countsUnanalysedTraining,
            interference: interference,
            weeklyMetrics: weeklyMetrics,
            sessionsInWindow: sessionsInWindow,
            sessionsInLastSevenDays: sessionsInLastSevenDays
        )
    }

    private func progression(_ exercise: String, from: Double, to: Double) -> AnalysisCard {
        .progression(exercise: exercise, muscleGroup: "Shoulders", fromKg: from, toKg: to, reasoning: "Reps held.")
    }

    private func benchPress(from: Double, to: Double) -> AnalysisCard {
        .progression(exercise: "Bench Press", muscleGroup: "Chest", fromKg: from, toKg: to, reasoning: "Clean overload.")
    }

    private func chestVersusLegs(_ chest: Double, _ legs: Double) -> AnalysisCard {
        .imbalance(groupA: "Chest", perWeekA: chest, groupB: "Legs", perWeekB: legs, reasoning: "Add a leg session.")
    }
}
