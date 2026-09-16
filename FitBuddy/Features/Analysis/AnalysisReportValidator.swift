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
/// worth reading. Only a card without any text is dropped, because its note
/// would be empty — and cards past `maxCards`.
enum AnalysisReportValidator {
    /// How far a progression's `fromKg` may sit from the listed working
    /// weight: rounding by the model, e.g. `61.25` written as `61`.
    static let weightToleranceKg = 0.5

    /// The smallest load increase always allowed, whatever the working
    /// weight: one barbell step (prompt rule 6, #173). Keeps a light dumbbell,
    /// where `maxStepShare` would allow less than one plate pair, progressable.
    static let minimumStepKg = 2.5

    /// Cards the result screen shows at most (design 3.4/3.5: one to four).
    static let maxCards = 4

    /// Title of a downgraded card that has no better one.
    static let fallbackNoteTitle = "Recommendation"

    /// Title of a downgraded recovery card.
    static let recoveryNoteTitle = "Recovery"

    /// The headline of a report the app turned into a recovery verdict
    /// (US-14 AC4).
    static let recoveryHeadline = "Recover this week."

    /// The reasoning of a recovery card the app inserts when the model left it
    /// out, or sent it without a reason (US-14 AC4).
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
        var verdict = report.verdict
        var headline = report.headline

        // US-3 AC6 / US-14 AC4: at 6 of 7 days no progression is shown without
        // the recovery hint, and the headline says so. A model recovery card
        // always survives at that count, so a missing one means the model left
        // it out.
        if evidence.recovery.needsRecovery {
            if !cards.contains(where: { $0.kind == .recovery }) {
                cards.insert(
                    .recovery(reasoning: insertedRecoveryReasoning, metrics: evidence.recovery),
                    at: 0
                )
            }
            if verdict != .recover {
                verdict = .recover
                headline = recoveryHeadline
            }
        }

        return ValidatedAnalysisReport(
            headline: headline,
            verdict: verdict,
            cards: capped(cards),
            summary: report.summary
        )
    }

    /// One card, validated: the app's version of it, its downgrade to a note,
    /// or `nil` when it has no text left to show.
    static func validate(_ card: AnalysisCard, against evidence: AnalysisReportEvidence) -> AnalysisReportCard? {
        switch card {
        case let .progression(exercise, _, fromKg, toKg, reasoning):
            if !isBlank(reasoning),
               let valid = progression(
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
            // Kept only when the app's own count calls for recovery. The issue
            // also accepts "the model explains it", but the schema forces a
            // reasoning onto every card, so that condition would keep every
            // recovery card — "0 sessions / 7 days" after a break included.
            // The model's suggestedRestHours is ignored: every figure on the
            // card is the app's.
            guard evidence.recovery.needsRecovery else {
                return note(title: recoveryNoteTitle, text: reasoning)
            }
            return .recovery(
                reasoning: isBlank(reasoning) ? insertedRecoveryReasoning : reasoning,
                metrics: evidence.recovery
            )

        case let .imbalance(groupA, perWeekA, groupB, perWeekB, reasoning):
            if !isBlank(reasoning),
               let valid = imbalance(
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
            guard !isBlank(text) else { return nil }
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
    /// - `toKg` is above that working weight, by at most
    ///   `max(minimumStepKg, working × AnalysisPromptBuilder.maxStepShare)` —
    ///   the step prompt rule 6 allows (#173).
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
        guard let match else { return nil }
        let maxStep = max(minimumStepKg, match.workingKg * AnalysisPromptBuilder.maxStepShare)
        guard toKg > match.workingKg, toKg - match.workingKg <= maxStep + epsilon else { return nil }
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
    /// - both groups name a `MuscleGroup` other than `.other` (trimmed,
    ///   case-insensitive) and differ from each other — `.other` is cardio and
    ///   unrecognised movements, not a muscle group to balance,
    /// - both per-week figures equal the app's at the prompt's precision
    ///   (`MuscleGroupFrequency.decimals`): the model's figure is rounded the
    ///   same way and must then be the same number. A group the window never
    ///   trained counts as 0,
    /// - the app's two figures differ: equal frequencies are no imbalance.
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
              a != b, a != .other, b != .other
        else { return nil }
        let appA = frequencies[a] ?? 0
        let appB = frequencies[b] ?? 0
        guard matchesFrequency(perWeekA, appA),
              matchesFrequency(perWeekB, appB),
              !matchesFrequency(appA, appB)
        else { return nil }
        return .imbalance(groupA: a, perWeekA: appA, groupB: b, perWeekB: appB, reasoning: reasoning)
    }

    private static func matchesFrequency(_ lhs: Double, _ rhs: Double) -> Bool {
        let decimals = MuscleGroupFrequency.decimals
        return abs(
            PlainWeightFormatter.rounded(lhs, decimals: decimals)
                - PlainWeightFormatter.rounded(rhs, decimals: decimals)
        ) < epsilon
    }

    // MARK: - Card count

    /// `cards` cut down to `maxCards`: notes go first, from the end, then the
    /// last card that is not a recovery card. The recovery hint is never cut
    /// (US-14 AC4); only when every card left is one does the last one go, so
    /// a single recovery card always remains.
    private static func capped(_ cards: [AnalysisReportCard]) -> [AnalysisReportCard] {
        var cards = cards
        while cards.count > maxCards {
            let index = cards.lastIndex { $0.kind == .note }
                ?? cards.lastIndex { $0.kind != .recovery }
                ?? cards.count - 1
            cards.remove(at: index)
        }
        return cards
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
