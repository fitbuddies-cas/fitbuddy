import Foundation

#if DEBUG
/// Validated reports shaped like design 3.4 and 3.5, for the card previews and
/// for the analysis a UI test seeds (#177).
///
/// Built directly as `ValidatedAnalysisReport`s: a live preview has no exercise
/// cache to validate against (#178), and these are the cards as the validator
/// hands them to the screen.
enum AnalysisReportSamples {
    /// Design 3.4: two progressions and an imbalance.
    static let progress = ValidatedAnalysisReport(
        headline: "You're ready to progress.",
        verdict: .progress,
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
        cards: [recoveryCard],
        summary: "You trained 6 of the last 7 days. Take two rest days before adding load."
    )

    /// No verdict either way: a note only.
    static let hold = ValidatedAnalysisReport(
        headline: "Hold steady this week.",
        verdict: .hold,
        cards: [noteCard],
        summary: "Keep your current loads for another week."
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

    static let noteCard = AnalysisReportCard.note(
        title: "Rows",
        text: "Add a rep on rows before adding weight — the last two sessions stalled at 8."
    )
}
#endif
