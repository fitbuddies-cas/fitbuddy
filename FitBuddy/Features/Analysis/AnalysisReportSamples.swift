import Foundation

#if DEBUG
/// Validated reports shaped like design 3.4, 3.4b, 3.4c, 3.4d and 3.5, for the card
/// previews and for the analysis a UI test seeds (#177, #170).
///
/// Built directly as `ValidatedAnalysisReport`s: a live preview has no exercise
/// cache to validate against (#178), and these are the cards as the validator
/// hands them to the screen.
enum AnalysisReportSamples {
    /// Design 3.4: two progressions and an imbalance.
    static let progress = ValidatedAnalysisReport(
        headline: "You're ready to progress.",
        verdict: .progress,
        lead: "Bench press and back squat are ready for 2.5 kg more. Legs need a second session first.",
        cards: [progressionCard, squatCard, imbalanceCard],
        summary: """
            Bench press is ready for 62.5 kg and back squat for 82.5 kg. \
            Give legs a second session before pushing chest further.
            """
    )

    /// Design 3.5: six of the last seven days, recovery before anything else.
    static let recover = ValidatedAnalysisReport(
        headline: "Recover this week.",
        verdict: .recover,
        lead: "Six training days out of seven: rest comes before any new load.",
        cards: [recoveryCard],
        summary: "You trained 6 of the last 7 days. Take two rest days before adding load."
    )

    /// No verdict either way: a note only.
    static let hold = ValidatedAnalysisReport(
        headline: "Hold steady this week.",
        verdict: .hold,
        lead: "Keep your current loads for another week.",
        cards: [noteCard],
        summary: """
            Rows stalled at 8 reps for the last two sessions, and no other lift \
            has a clean overload signal yet. Keep your current loads for another \
            week and add a rep on rows before adding weight.
            """
    )

    /// Design 3.4b: too little data for any card — the lead and the full
    /// analysis carry the answer, and the disclosure starts open.
    static let thin = ValidatedAnalysisReport(
        headline: "Hold steady this week.",
        verdict: .hold,
        lead: "Two sessions in four weeks are too few to judge a trend. Keep your current weights and log a few more sessions.",
        cards: [],
        summary: """
            You logged two sessions in the last four weeks, both upper body.

            **What the data shows**
            Bench press and rows each appear once, at the same weights as \
            before. One session per movement says nothing yet about whether \
            a load is getting easier.

            - Keep your current weights for the next sessions
            - Log two to three sessions a week so a trend can show
            """
    )

    /// The fourth verdict class (#227, ADR-014 §6): the app's headline, the
    /// app's lead and the note naming the condition that fired — the same
    /// shape as design 3.4b, which the mock draws with a `hold`.
    static let insufficientData = ValidatedAnalysisReport(
        headline: AnalysisReportValidator.insufficientDataHeadline,
        verdict: .insufficientData,
        lead: AnalysisReportValidator.insufficientDataLead,
        cards: [noVerdictNoteCard],
        summary: """
            You logged three sessions in the last four weeks. Bench press and \
            rows appear twice each, at the same weights — too little to tell a \
            plateau from a session that simply went well.
            """
    )

    /// The note the app writes above an `insufficientData` report.
    static let noVerdictNoteCard = AnalysisReportCard.note(
        title: AnalysisReportValidator.insufficientDataNoteTitle,
        text: "This analysis covers 3 of the 4 sessions the app needs before it reads a trend."
    )

    static let progressionCard = AnalysisReportCard.progression(
        exercise: "Bench Press (Barbell)",
        muscleGroup: .chest,
        fromKg: 60,
        toKg: 62.5,
        reasoning: "3 sessions at 60×5 with RPE ≤7 — clean overload signal."
    )

    static let squatCard = AnalysisReportCard.progression(
        exercise: "Squat (Barbell)",
        muscleGroup: .legs,
        fromKg: 80,
        toKg: 82.5,
        reasoning: "Estimated 1RM up 4 % in 4 weeks, reps held across all sets."
    )

    /// US-17 AC3 (#234): the lever where no load step fits — two more reps
    /// at the same dumbbell.
    static let repProgressionCard = AnalysisReportCard.repProgression(
        exercise: "Lateral Raise (Dumbbell)",
        muscleGroup: .shoulders,
        weightKg: 10,
        fromReps: 12,
        toReps: 14,
        reasoning: "Twelve clean reps for three sessions and the next dumbbell is a 20 % jump — earn it with reps first."
    )

    static let imbalanceCard = AnalysisReportCard.imbalance(
        groupA: .chest,
        perWeekA: 3,
        groupB: .legs,
        perWeekB: 1,
        reasoning: "Add a second leg session this week (squat or RDL focus) before pushing chest further."
    )

    static let recoveryCard = AnalysisReportCard.recovery(
        reasoning: """
            Before adding load to chest or legs, take two rest days and one deload \
            session at ~60 % of your usual sets.
            """,
        metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2)
    )

    /// The recovery card of a week whose sets logged no RPE: the cell drops.
    static let recoveryCardWithoutRPE = AnalysisReportCard.recovery(
        reasoning: "Take two rest days before the next heavy session.",
        metrics: RecoveryMetrics(sessions: 7, trainingDays: 7, averageRPE: nil)
    )

    /// A mixed week (#184): four strength sessions and two runs on six days,
    /// with both means recorded — the widest the metrics row ever gets.
    static let recoveryCardMixedWeek = AnalysisReportCard.recovery(
        reasoning: """
            Four strength sessions and two runs on six days leave no day for \
            adaptation: take two rest days before the next hard session.
            """,
        metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2, averageHeartRate: 148)
    )

    /// Design 3.4c: the Endurance profile, stated in kilometres.
    static let weeklyDistanceCard = AnalysisReportCard.metric(
        label: "Weekly distance",
        from: 32,
        to: 35,
        unit: .kilometers,
        reasoning: "32 km held for three weeks at an unchanged easy heart rate — room for roughly 10 % more.",
        source: "Run"
    )

    /// The same card in a unit where a lower figure is the better one, and
    /// without a source label — a card with nothing to put there draws none.
    static let easyPaceCard = AnalysisReportCard.metric(
        label: "Easy pace",
        from: 6,
        to: 5 + 20.0 / 60,
        unit: .minutesPerKilometer,
        reasoning: "The easy runs have drifted quick; hold them slower while the distance goes up.",
        source: ""
    )

    /// Design 3.4d: both domains in the same week.
    static let interferenceCard = AnalysisReportCard.interference(
        metrics: InterferenceMetrics(strengthDays: 4, cardioDays: 4, overlapDays: 3),
        reasoning: """
            Move one run onto a day without lifting — the overlap costs you \
            more than the extra session gains.
            """
    )

    /// Design 3.4c: an endurance analysis, with no kilogram on the screen
    /// (US-15 AC5).
    static let endurance = ValidatedAnalysisReport(
        headline: "You're ready to progress.",
        verdict: .progress,
        lead: "Your weekly distance held at 32 km for three weeks at an easy heart rate. 35 km is the next step.",
        cards: [weeklyDistanceCard, easyPaceCard],
        summary: """
            Weekly distance sat at 30 to 32 km for three weeks while your mean \
            heart rate on the easy runs fell. Add about 3 km next week, all of \
            it to the long run, and keep the easy pace where it is.
            """
    )

    /// Design 3.4d: the overall-load analysis, led by the interference card.
    static let overallLoad = ValidatedAnalysisReport(
        headline: "Hold steady this week.",
        verdict: .hold,
        lead: "Strength and running landed on the same three days last week. Separate them before adding anything.",
        cards: [interferenceCard, weeklyDistanceCard],
        summary: """
            On three of the last seven days a run and a lifting session shared \
            the day. That is the pattern to change before either side goes up.
            """
    )

    static let noteCard = AnalysisReportCard.note(
        title: "Rows",
        text: "Add a rep on rows before adding weight — the last two sessions stalled at 8."
    )
}
#endif
