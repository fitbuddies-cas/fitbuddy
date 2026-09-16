import Foundation
@testable import FitBuddy

/// Sample structured answers, as a provider sends them and as they decode
/// (#174). One report carries every card kind, so a single fixture exercises
/// the whole schema.
enum AnalysisReportFixtures {
    /// A wire answer with one card of each kind, `summary` ahead of `cards` as
    /// the schema declares it.
    static let progressJSON = """
    {
      "headline": "You're ready to progress.",
      "verdict": "progress",
      "summary": "Bench press is ready for 62.5 kg. Legs need a second session.",
      "cards": [
        {
          "kind": "progression",
          "exercise": "Bench Press",
          "muscleGroup": "Chest",
          "fromKg": 60,
          "toKg": 62.5,
          "reasoning": "3 sessions at 60 kg x 5 with RPE 7 or lower."
        },
        {
          "kind": "recovery",
          "reasoning": "Take a rest day before the next heavy session.",
          "suggestedRestHours": 48
        },
        {
          "kind": "imbalance",
          "groupA": "Chest",
          "perWeekA": 3,
          "groupB": "Legs",
          "perWeekB": 1,
          "reasoning": "Add a second leg session this week."
        },
        {
          "kind": "note",
          "title": "Pull-ups",
          "text": "Add one rep per set before adding weight."
        }
      ]
    }
    """

    /// `progressJSON`, decoded.
    static let progress = AnalysisReport(
        headline: "You're ready to progress.",
        verdict: .progress,
        cards: [
            .progression(
                exercise: "Bench Press",
                muscleGroup: "Chest",
                fromKg: 60,
                toKg: 62.5,
                reasoning: "3 sessions at 60 kg x 5 with RPE 7 or lower."
            ),
            .recovery(reasoning: "Take a rest day before the next heavy session.", suggestedRestHours: 48),
            .imbalance(
                groupA: "Chest",
                perWeekA: 3,
                groupB: "Legs",
                perWeekB: 1,
                reasoning: "Add a second leg session this week."
            ),
            .note(title: "Pull-ups", text: "Add one rep per set before adding weight.")
        ],
        summary: "Bench press is ready for 62.5 kg. Legs need a second session."
    )

    /// `progressJSON` split into `count` roughly equal chunks, the way a
    /// stream delivers it.
    static func progressChunks(_ count: Int = 5) -> [String] {
        let characters = Array(progressJSON)
        let size = max(1, characters.count / count)
        return stride(from: 0, to: characters.count, by: size).map {
            String(characters[$0..<min($0 + size, characters.count)])
        }
    }
}
