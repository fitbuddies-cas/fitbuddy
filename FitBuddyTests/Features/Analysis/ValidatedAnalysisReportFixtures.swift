import Foundation
@testable import FitBuddy

/// A validated report as the history stores it (#176): one card of each kind,
/// including the app-computed recovery metrics, so a round trip through
/// persistence covers every field that has to survive.
enum ValidatedAnalysisReportFixtures {
    static let everyCard = ValidatedAnalysisReport(
        headline: "Recover this week.",
        verdict: .recover,
        lead: "Rest two days before adding load.",
        cards: [
            .recovery(
                reasoning: "Six training days in a row — rest before adding load.",
                metrics: RecoveryMetrics(sessions: 7, trainingDays: 6, averageRPE: 8.5)
            ),
            .progression(
                exercise: "Bench Press (Barbell)",
                muscleGroup: .chest,
                fromKg: 60,
                toKg: 62.5,
                reasoning: "Five sessions at 60 kg with the reps held."
            ),
            .imbalance(
                groupA: .chest,
                perWeekA: 2.5,
                groupB: .legs,
                perWeekB: 0.8,
                reasoning: "Legs get a third of the chest's sessions."
            ),
            .note(title: "Reps first", text: "Add a rep on rows before adding weight."),
        ],
        summary: "Rest two days, then add 2.5 kg on bench and give legs a second slot."
    )
}
