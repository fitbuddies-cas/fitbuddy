import Foundation
@testable import FitBuddy

/// The one place tests get analysis reports from (#179): the model's answer as
/// a provider sends it (`AnalysisReport`, #174), the validated report as the
/// history stores it (`ValidatedAnalysisReport`, #175/#176), and the answers
/// the two analysis mock profiles are run against.
///
/// Replaces `AnalysisReportFixtures` and `ValidatedAnalysisReportFixtures`.
/// The validated reports per verdict are not repeated here: they are
/// `AnalysisReportSamples`, which live in the app target (DEBUG) because the
/// previews and `MockAnalysisSeeder` — the UI test's seam — need them too, and
/// the app cannot reach the test target. `validated(_:)` hands them out.
///
/// `card(_:)`, `report(_:)` and `validatedCard(_:)` switch over every kind and
/// verdict, so a new one fails to compile here until it has a fixture.
enum AnalysisReportFactory {
    // MARK: - Model answers

    /// A wire answer with one card of each kind, `lead` and `summary` ahead of
    /// `cards` as the schema declares them.
    static let progressJSON = """
    {
      "headline": "You're ready to progress.",
      "verdict": "progress",
      "lead": "Bench press can go up. Legs are behind.",
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
          "kind": "metric",
          "label": "Weekly distance",
          "from": 32,
          "to": 35,
          "unit": "kilometers",
          "reasoning": "32 km held for three weeks at an unchanged easy heart rate.",
          "source": "Run"
        },
        {
          "kind": "interference",
          "strengthDays": 4,
          "cardioDays": 4,
          "overlapDays": 3,
          "reasoning": "Move one run onto a day without lifting."
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
        lead: "Bench press can go up. Legs are behind.",
        cards: AnalysisCard.Kind.allCases.map(card),
        summary: "Bench press is ready for 62.5 kg. Legs need a second session."
    )

    /// A recovery week: the recovery card first, a note after it.
    static let recover = AnalysisReport(
        headline: "Recover this week.",
        verdict: .recover,
        lead: "Rest comes before any new load this week.",
        cards: [card(.recovery), card(.note)],
        summary: "You trained almost every day. Rest for two days before adding load."
    )

    /// Neither progress nor rest: a note only.
    static let hold = AnalysisReport(
        headline: "Hold steady this week.",
        verdict: .hold,
        lead: "Keep your current loads for another week.",
        cards: [card(.note)],
        summary: "Keep your current loads for another week."
    )

    /// Thin data (#170): nothing supports a card, so there is none — the lead
    /// and the summary carry the answer.
    static let thin = AnalysisReport(
        headline: "Hold steady this week.",
        verdict: .hold,
        lead: "Two sessions are too few to judge a trend. Keep your current weights.",
        cards: [],
        summary: "You logged two sessions in four weeks. Keep your current weights and log a few more sessions."
    )

    /// A model answer of each verdict.
    static func report(_ verdict: AnalysisVerdict) -> AnalysisReport {
        switch verdict {
        case .progress: return progress
        case .recover: return recover
        case .hold: return hold
        }
    }

    /// One model card of each kind — the cards of `progress`, in order.
    static func card(_ kind: AnalysisCard.Kind) -> AnalysisCard {
        switch kind {
        case .progression:
            return .progression(
                exercise: "Bench Press",
                muscleGroup: "Chest",
                fromKg: 60,
                toKg: 62.5,
                reasoning: "3 sessions at 60 kg x 5 with RPE 7 or lower."
            )
        case .recovery:
            return .recovery(reasoning: "Take a rest day before the next heavy session.", suggestedRestHours: 48)
        case .imbalance:
            return .imbalance(
                groupA: "Chest",
                perWeekA: 3,
                groupB: "Legs",
                perWeekB: 1,
                reasoning: "Add a second leg session this week."
            )
        case .metric:
            return .metric(
                label: "Weekly distance",
                from: 32,
                to: 35,
                unit: .kilometers,
                reasoning: "32 km held for three weeks at an unchanged easy heart rate.",
                source: "Run"
            )
        case .interference:
            return .interference(
                strengthDays: 4,
                cardioDays: 4,
                overlapDays: 3,
                reasoning: "Move one run onto a day without lifting."
            )
        case .note:
            return .note(title: "Pull-ups", text: "Add one rep per set before adding weight.")
        }
    }

    /// `progressJSON` split into `count` roughly equal chunks, the way a
    /// stream delivers it.
    static func progressChunks(_ count: Int = 5) -> [String] {
        let characters = Array(progressJSON)
        let size = max(1, characters.count / count)
        return stride(from: 0, to: characters.count, by: size).map {
            String(characters[$0..<min($0 + size, characters.count)])
        }
    }

    // MARK: - Validated reports

    /// One validated card of each kind, including the app-computed recovery
    /// metrics, so a round trip through persistence covers every field that
    /// has to survive.
    static let validatedEveryCard = ValidatedAnalysisReport(
        headline: "Recover this week.",
        verdict: .recover,
        lead: "Rest two days before adding load.",
        cards: [
            validatedCard(.recovery),
            validatedCard(.progression),
            validatedCard(.imbalance),
            validatedCard(.metric),
            validatedCard(.interference),
            validatedCard(.note),
        ],
        summary: "Rest two days, then add 2.5 kg on bench and give legs a second slot."
    )

    /// One validated card of each kind — the cards of `validatedEveryCard`.
    static func validatedCard(_ kind: AnalysisCard.Kind) -> AnalysisReportCard {
        switch kind {
        case .progression:
            return .progression(
                exercise: "Bench Press (Barbell)",
                muscleGroup: .chest,
                fromKg: 60,
                toKg: 62.5,
                reasoning: "Five sessions at 60 kg with the reps held."
            )
        case .recovery:
            return .recovery(
                reasoning: "Six training days in a row — rest before adding load.",
                metrics: RecoveryMetrics(sessions: 7, trainingDays: 6, averageRPE: 8.5)
            )
        case .imbalance:
            return .imbalance(
                groupA: .chest,
                perWeekA: 2.5,
                groupB: .legs,
                perWeekB: 0.8,
                reasoning: "Legs get a third of the chest's sessions."
            )
        case .metric:
            return .metric(
                label: "Weekly distance",
                from: 32,
                to: 35,
                unit: .kilometers,
                reasoning: "32 km held for three weeks at an unchanged easy heart rate.",
                source: "Run"
            )
        case .interference:
            return .interference(
                metrics: InterferenceMetrics(strengthDays: 4, cardioDays: 4, overlapDays: 3),
                reasoning: "Move one run onto a day without lifting."
            )
        case .note:
            return .note(title: "Reps first", text: "Add a rep on rows before adding weight.")
        }
    }

    /// A validated report of each verdict, shaped like design 3.4/3.5. The
    /// report without cards of design 3.4b is `AnalysisReportSamples.thin`.
    static func validated(_ verdict: AnalysisVerdict) -> ValidatedAnalysisReport {
        switch verdict {
        case .progress: return AnalysisReportSamples.progress
        case .recover: return AnalysisReportSamples.recover
        case .hold: return AnalysisReportSamples.hold
        }
    }

    // MARK: - Mock profiles

    /// The working weight the `progression-ready` profile ends bench press on.
    static let progressionReadyBenchKg = 60.0

    /// The working weight the `overreached` profile ends bench press on.
    static let overreachedBenchKg = 70.0

    /// What a model answers for `MockWorkoutProfile.progressionReady`: one
    /// barbell step on bench press, from the weight its prompt line names.
    static let progressionReady = AnalysisReport(
        headline: "You're ready to progress.",
        verdict: .progress,
        lead: "Bench press is ready for 62.5 kg.",
        cards: [
            .progression(
                exercise: "Bench Press (Barbell)",
                muscleGroup: "Chest",
                fromKg: progressionReadyBenchKg,
                toKg: progressionReadyBenchKg + 2.5,
                reasoning: "3 sessions at 60 kg × 5 with RPE 7 or lower — clean overload signal."
            ),
        ],
        summary: "Bench press held 60 kg × 5 for three sessions at RPE 7. Add 2.5 kg next session."
    )

    /// What a model might answer for `MockWorkoutProfile.overreached` when it
    /// misses the week: a load increase and no recovery card. The validator
    /// has to add the recovery hint and turn the verdict (US-14 AC4).
    static let overreached = AnalysisReport(
        headline: "You're ready to progress.",
        verdict: .progress,
        lead: "Bench press can go up to 72.5 kg.",
        cards: [
            .progression(
                exercise: "Bench Press (Barbell)",
                muscleGroup: "Chest",
                fromKg: overreachedBenchKg,
                toKg: overreachedBenchKg + 2.5,
                reasoning: "Two sessions at 70 kg × 5 this week."
            ),
        ],
        summary: "Bench press moved to 70 kg. Add 2.5 kg next session."
    )

    // MARK: - Cross-source mock profiles (#188)

    /// The step a metric card proposes on a weekly figure: a tenth more,
    /// rounded to what the unit prints.
    ///
    /// Taken from the app's own figure rather than written down, because
    /// `AnalysisReportValidator` requires a card's `from` to *be* the app's
    /// figure at the prompt's precision (#186). A fixture that spelled a
    /// number would validate only until somebody touched the payload.
    static func metricStep(from figure: Double) -> Double {
        (figure * 1.1).rounded()
    }

    /// What a model answers for `MockWorkoutProfile.runner`: one metric card
    /// on the weekly distance, anchored on the week's own figure.
    ///
    /// Everything on it is endurance — kilometres, a run as the source, not a
    /// kilogram anywhere (US-15 AC5).
    static func runner(weeklyKilometers: Double) -> AnalysisReport {
        AnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            lead: "The weekly distance has been steady at an easy heart rate — it can grow.",
            cards: [
                .metric(
                    label: "Weekly distance",
                    from: weeklyKilometers,
                    to: metricStep(from: weeklyKilometers),
                    unit: .kilometers,
                    reasoning: "Three weeks at the same distance with an unchanged easy heart rate.",
                    source: "Run"
                ),
            ],
            summary: "Four runs a week at a steady heart rate. Add a few kilometres to the long run."
        )
    }

    /// What a model answers for `MockWorkoutProfile.mixed` under "Overall
    /// load": the interference card of design 3.4d with a metric card under
    /// it. The day counts are the model's guess — the app replaces them with
    /// its own (#186).
    static func mixedOverallLoad(weeklyKilometers: Double) -> AnalysisReport {
        AnalysisReport(
            headline: "Hold steady this week.",
            verdict: .hold,
            lead: "Two of the three endurance sessions sit on a lifting day.",
            cards: [
                .interference(
                    strengthDays: 3,
                    cardioDays: 3,
                    overlapDays: 2,
                    reasoning: "Move the easy run onto a day without lifting."
                ),
                .metric(
                    label: "Weekly distance",
                    from: weeklyKilometers,
                    to: metricStep(from: weeklyKilometers),
                    unit: .kilometers,
                    reasoning: "The distance has been level while the lifting week grew.",
                    source: "Run"
                ),
            ],
            summary: "Keep the week as it is and move one run off a lifting day."
        )
    }
}
