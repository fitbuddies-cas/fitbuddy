import Foundation

/// Checks the cards of a model's `AnalysisReport` against the cache (US-14
/// AC3/AC4, #175).
///
/// The schema guarantees a card's shape, not its truth. A card reading "Bench
/// Press 60 → 62.5 kg" may only appear when bench press was in the prompt and
/// 60 kg was the working weight the prompt named — otherwise it is an invented
/// number laid out like a measurement.
///
/// A card that fails is downgraded to a `.note` with the model's reasoning,
/// not dropped: the user paid for the answer, and the sentence may still be
/// worth reading. Only a failed card without any reasoning is dropped, because
/// its note would be empty.
enum AnalysisReportValidator {
    /// How far a progression's `fromKg` may sit from the listed working
    /// weight: rounding by the model, e.g. `61.25` written as `61`.
    static let weightToleranceKg = 0.5

    /// Title of a downgraded card that has no better one.
    static let fallbackNoteTitle = "Recommendation"

    /// Title of a downgraded recovery card.
    static let recoveryNoteTitle = "Recovery"

    /// The reasoning of the recovery card the app inserts when the model left
    /// it out (US-14 AC4).
    static let insertedRecoveryReasoning =
        "Recovery comes before progression: take the suggested rest before adding load to any exercise."

    /// Validates every card and enforces the recovery hint.
    ///
    /// - Parameters:
    ///   - report: The model's answer, as decoded.
    ///   - evidence: The cache's facts about the window the prompt described.
    static func validate(
        _ report: AnalysisReport,
        against evidence: AnalysisReportEvidence
    ) -> ValidatedAnalysisReport {
        var cards = report.cards.compactMap { validate($0, against: evidence) }

        // US-3 AC6 / US-14 AC4: at 6 of 7 days no progression is shown without
        // the recovery hint. A model recovery card always survives at that
        // count, so a missing one means the model left it out.
        if evidence.recovery.needsRecovery,
           !cards.contains(where: { $0.kind == .recovery }) {
            cards.insert(
                .recovery(reasoning: insertedRecoveryReasoning, metrics: evidence.recovery),
                at: 0
            )
        }

        return ValidatedAnalysisReport(
            headline: report.headline,
            verdict: report.verdict,
            cards: cards,
            summary: report.summary
        )
    }

    /// One card, validated: the app's version of it, its downgrade to a note,
    /// or `nil` when it failed and has nothing left to say.
    static func validate(_ card: AnalysisCard, against evidence: AnalysisReportEvidence) -> AnalysisReportCard? {
        switch card {
        case let .progression(exercise, _, fromKg, toKg, reasoning):
            if let valid = progression(
                exercise: exercise,
                fromKg: fromKg,
                toKg: toKg,
                reasoning: reasoning,
                listed: evidence.exercises
            ) {
                return valid
            }
            return note(title: trimmed(exercise), text: reasoning)

        case let .recovery(reasoning, _):
            // The model's suggestedRestHours is ignored: every figure on the
            // card is the app's.
            guard evidence.recovery.needsRecovery || !isBlank(reasoning) else {
                return note(title: recoveryNoteTitle, text: reasoning)
            }
            return .recovery(reasoning: reasoning, metrics: evidence.recovery)

        case let .imbalance(groupA, perWeekA, groupB, perWeekB, reasoning):
            if let valid = imbalance(
                groupA: groupA,
                perWeekA: perWeekA,
                groupB: groupB,
                perWeekB: perWeekB,
                reasoning: reasoning,
                frequencies: evidence.muscleGroupsPerWeek
            ) {
                return valid
            }
            return note(title: fallbackNoteTitle, text: reasoning)

        case let .note(title, text):
            return .note(title: title, text: text)
        }
    }

    // MARK: - Progression

    /// The progression as the app states it, or `nil` when the cache does not
    /// back it:
    ///
    /// - the exercise is listed in the prompt (trimmed, case-insensitive),
    /// - its listed working weight exists and `fromKg` is within
    ///   `weightToleranceKg` of it,
    /// - `toKg` is above that working weight.
    ///
    /// Title, muscle group and `fromKg` are replaced by the listed values, so
    /// the struck-through figure on the card is the cache's, not the model's
    /// rounding of it. Where two listed exercises share a title, the first
    /// whose weight matches wins.
    private static func progression(
        exercise: String,
        fromKg: Double,
        toKg: Double,
        reasoning: String,
        listed: [ListedExercise]
    ) -> AnalysisReportCard? {
        let name = folded(exercise)
        let match = listed.lazy
            .filter { folded($0.title) == name }
            .compactMap { listed -> (exercise: ListedExercise, workingKg: Double)? in
                guard let working = listed.workingSet?.roundedWeightKg,
                      abs(fromKg - working) <= weightToleranceKg + epsilon
                else { return nil }
                return (listed, working)
            }
            .first
        guard let match, toKg > match.workingKg else { return nil }
        return .progression(
            exercise: match.exercise.title,
            muscleGroup: match.exercise.muscleGroup,
            fromKg: match.workingKg,
            toKg: toKg,
            reasoning: reasoning
        )
    }

    // MARK: - Imbalance

    /// The imbalance with the app's figures, or `nil` when the cache does not
    /// back it:
    ///
    /// - both groups name a `MuscleGroup` (trimmed, case-insensitive) and
    ///   differ from each other,
    /// - both per-week figures equal the app's at the prompt's precision
    ///   (`MuscleGroupFrequency.decimals`): the model's figure is rounded the
    ///   same way and must then be the same number. A group the window never
    ///   trained counts as 0.
    private static func imbalance(
        groupA: String,
        perWeekA: Double,
        groupB: String,
        perWeekB: Double,
        reasoning: String,
        frequencies: [MuscleGroup: Double]
    ) -> AnalysisReportCard? {
        guard let a = MuscleGroup(rawValue: folded(groupA)),
              let b = MuscleGroup(rawValue: folded(groupB)),
              a != b
        else { return nil }
        let appA = frequencies[a] ?? 0
        let appB = frequencies[b] ?? 0
        guard matchesFrequency(perWeekA, appA), matchesFrequency(perWeekB, appB) else { return nil }
        return .imbalance(groupA: a, perWeekA: appA, groupB: b, perWeekB: appB, reasoning: reasoning)
    }

    private static func matchesFrequency(_ model: Double, _ app: Double) -> Bool {
        let decimals = MuscleGroupFrequency.decimals
        return abs(
            PlainWeightFormatter.rounded(model, decimals: decimals)
                - PlainWeightFormatter.rounded(app, decimals: decimals)
        ) < epsilon
    }

    // MARK: - Helpers

    /// Absorbs floating-point noise in comparisons of figures that are equal
    /// on paper.
    private static let epsilon = 1e-6

    /// A failed card as a note, or `nil` when it has no text to show.
    private static func note(title: String, text: String) -> AnalysisReportCard? {
        guard !isBlank(text) else { return nil }
        return .note(title: title.isEmpty ? fallbackNoteTitle : title, text: text)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func folded(_ text: String) -> String {
        trimmed(text).lowercased()
    }

    private static func isBlank(_ text: String) -> Bool {
        trimmed(text).isEmpty
    }
}
