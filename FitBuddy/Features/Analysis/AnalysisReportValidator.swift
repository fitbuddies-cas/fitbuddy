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

    /// The barbell step prompt rule 6 names (#173): the load increase a
    /// barbell exercise is allowed, whatever step is listed for it. The
    /// prompt's own constant, so the two cannot drift apart.
    static let minimumStepKg = AnalysisPromptBuilder.minimumStepKg

    /// Cards the result screen shows at most (design 3.4/3.4b/3.5: zero to four).
    static let maxCards = 4

    /// Title of a downgraded card that has no better one.
    static let fallbackNoteTitle = "Recommendation"

    /// Title of a downgraded recovery card.
    static let recoveryNoteTitle = "Recovery"

    /// Title of a downgraded interference card.
    static let interferenceNoteTitle = "Training load"

    /// How far a metric card's `to` may sit from the app's figure, as a share
    /// of it.
    ///
    /// A fifth of the week's own figure. Past that the card is a number rather
    /// than a recommendation — no week's distance doubles on advice. The same
    /// bound in both directions, for the same reason prompt rule 6 caps a
    /// barbell step: the app has to be able to say why the figure is the one
    /// it prints.
    ///
    /// **`from` has no tolerance at all.** It used to allow 5 % — 620 kg of
    /// slack at a weekly volume of 12 400 kg, which let the card print one
    /// number while its own reasoning sentence argued from another. It is now
    /// an equality, at the precision the prompt printed the figure with
    /// (`MetricUnit.statesTheSameFigure(_:as:)`), which is the rule the
    /// imbalance card already follows: the model is quoting a figure it was
    /// given, so it must quote it. Where it does not, the card is downgraded
    /// to a note and its sentence still reaches the screen — the conservative
    /// failure, not a wrong measurement.
    static let metricStepShare = 0.2

    /// The headline of a report the app turned into a recovery verdict
    /// (US-14 AC4).
    static let recoveryHeadline = AnalysisHeadline.text(for: .recover)

    /// The lead of a report the app turned into a recovery verdict (US-14 AC4,
    /// #170). Replaces the model's, which was written for the verdict the app
    /// overruled and would contradict the headline right above it.
    ///
    /// `trainingDays` counts strength and endurance together since #184, and
    /// so does the sentence: "before adding load" was strength wording that
    /// said nothing to a week of six runs, and the app now points this lead at
    /// exactly such weeks.
    static func recoveryLead(trainingDays: Int) -> String {
        "You trained on \(trainingDays) of the last 7 days. "
            + "Take the suggested rest before your next hard session."
    }

    /// The headline of a progress report the app turned into a hold verdict,
    /// because no progression card is left to back it (#177).
    static let holdHeadline = AnalysisHeadline.text(for: .hold)

    /// The lead of a progress report the app turned into a hold verdict after
    /// taking away at least one of its progressions (#170). The model's lead
    /// argued for a load increase no card backs.
    static let holdLead =
        "Your data doesn't back a specific load increase yet. Keep your current weights and read the full analysis below."

    /// The lead of a report the app turned into a progress verdict, because
    /// its own figures carry the step the model argued against (ADR-013 §7).
    ///
    /// Says only what stage 4 measured. ADR-013 spells out the text for the
    /// fourth class but not for this case, so the wording is #227's; it was
    /// kept to the one statement the rule actually read.
    static let progressLead =
        "Your most recent session set the best estimated 1RM of the analysed window on at least one exercise. Read the full analysis below before adding load."

    /// The headline of a report without a verdict (ADR-013 §6). Same string
    /// `AnalysisHeadline` renders, so the stored report and the screen cannot
    /// say different things.
    static let insufficientDataHeadline = AnalysisHeadline.text(for: .insufficientData)

    /// The lead of a report without a verdict, word for word from ADR-013 §6.
    static let insufficientDataLead =
        "Your logged training doesn't yet support a recommendation for or against more load. Keep training as before — the next analysis will have more to go on."

    /// Title of the note that names why there is no verdict (ADR-013 §6).
    static let insufficientDataNoteTitle = "Why there's no verdict"

    /// The reasoning of a recovery card the app inserts when the model left it
    /// out, or sent it without a reason (US-14 AC4).
    ///
    /// Domain-neutral since #184: the card is now inserted for a week of runs
    /// as readily as for a week of lifts, and "before adding load to any
    /// exercise" named neither the training nor the advice of such a week.
    static let insertedRecoveryReasoning =
        "Recovery comes before progression: take the suggested rest before your next hard session."

    /// The same reasoning, with the sentence a single-domain profile needs
    /// (#185).
    ///
    /// The card's figures are profile-blind on purpose — one body has one
    /// recovery — so under "Strength" it can read "Sessions / 7d: 7" on a week
    /// that held two runs, next to a screen that mentions no running at all.
    /// Without this sentence that figure looks like a mistake; with it, it is
    /// the point.
    static func insertedRecoveryReasoning(countingUnanalysedTraining: Bool) -> String {
        guard countingUnanalysedTraining else { return insertedRecoveryReasoning }
        return insertedRecoveryReasoning
            + " These figures count every session of the week, including the training "
            + "this analysis left out."
    }

    /// Validates every card, and puts the app's own verdict over the model's.
    ///
    /// The verdict is no longer the model's since #227: `AnalysisVerdictRule`
    /// derives it from the evidence, this method applies it — replacing
    /// headline and lead where the two disagree, and taking away the cards a
    /// fourth-class verdict must not show (ADR-013 §6/§7). The model's own
    /// choice is kept on the report for #228.
    ///
    /// - Parameters:
    ///   - report: The model's answer, as decoded.
    ///   - evidence: The cache's facts about the window the prompt described.
    static func validate(
        _ report: AnalysisReport,
        against evidence: AnalysisReportEvidence
    ) -> ValidatedAnalysisReport {
        var cards = report.cards.compactMap { validate($0, against: evidence) }
        let outcome = AnalysisVerdictRule.outcome(for: evidence)
        let verdict = outcome.verdict
        var headline = report.headline
        var lead = report.lead

        // US-3 AC6 / US-14 AC4 / US-15 AC3: at 6 of 7 days no progression is
        // shown without the recovery hint. The count spans every source and
        // both domains since #184, so four strength sessions and two runs on
        // six days trigger the hint just as six strength sessions do. A model
        // recovery card always survives at that count, so a missing one means
        // the model left it out. This is the card side of ADR-013 stage 0;
        // the verdict side is in the rule.
        if evidence.recovery.needsRecovery, !cards.contains(where: { $0.kind == .recovery }) {
            cards.insert(
                .recovery(
                    reasoning: insertedRecoveryReasoning(
                        countingUnanalysedTraining: evidence.recoveryCountsUnanalysedTraining
                    ),
                    metrics: evidence.recovery
                ),
                at: 0
            )
        }

        // ADR-013 §6: without a verdict there is no card that would be one.
        // A progression card *is* a verdict, a recovery card is `recover`
        // under another name, and a metric card states a step nobody backed.
        // They are downgraded to notes rather than dropped, as everywhere else
        // in this file — the user paid for the sentence. Above them goes the
        // app's own note naming the condition that fired.
        if verdict == .insufficientData {
            cards = cards.compactMap(withoutAVerdict)
            if let note = insufficientDataNote(reason: outcome.reason, evidence: evidence) {
                cards.insert(note, at: 0)
            }
        }

        // Where the app's verdict differs from the model's, the model's
        // headline and lead argue for the call the app has just replaced, so
        // they go with it (ADR-013 §7). Where the two agree, the model keeps
        // its wording — the app overruled nothing in it.
        if verdict != report.verdict {
            headline = AnalysisHeadline.text(for: verdict)
            lead = self.lead(for: verdict, evidence: evidence)
        }

        return ValidatedAnalysisReport(
            headline: headline,
            verdict: verdict,
            lead: lead,
            cards: capped(cards),
            summary: report.summary,
            modelVerdict: report.verdict
        )
    }

    /// The app's lead for a verdict it put over the model's (ADR-013 §7).
    static func lead(for verdict: AnalysisVerdict, evidence: AnalysisReportEvidence) -> String {
        switch verdict {
        case .progress: return progressLead
        case .recover: return recoveryLead(trainingDays: evidence.recovery.trainingDays)
        case .hold: return holdLead
        case .insufficientData: return insufficientDataLead
        }
    }

    /// A validated card with whatever made it a verdict taken out of it, for
    /// an `insufficientData` report (ADR-013 §6).
    ///
    /// Imbalance and interference cards stay: every figure on them is one the
    /// app measured and replaced, and neither argues for or against load.
    /// A metric card does not stay, although ADR-013 names only progression
    /// and recovery — its `to` is a step, which is exactly what a report
    /// without a verdict must not print.
    private static func withoutAVerdict(_ card: AnalysisReportCard) -> AnalysisReportCard? {
        switch card {
        case let .progression(exercise, _, _, _, reasoning):
            return note(title: trimmed(exercise), text: reasoning)
        case let .recovery(reasoning, _):
            return note(title: recoveryNoteTitle, text: reasoning)
        case let .metric(label, _, _, _, reasoning, _):
            return note(title: trimmed(label), text: reasoning)
        case .imbalance, .interference, .note:
            return card
        }
    }

    /// The one note the app puts at the top of an `insufficientData` report,
    /// naming the condition that fired (ADR-013 §6).
    ///
    /// `nil` for a reason that never reaches this verdict.
    static func insufficientDataNote(
        reason: AnalysisVerdictRule.Reason,
        evidence: AnalysisReportEvidence
    ) -> AnalysisReportCard? {
        let text: String
        switch reason {
        case .tooFewSessions:
            text = "This analysis covers \(evidence.sessionsInWindow) of the "
                + "\(AnalysisVerdictRule.minimumSessionsInWindow) sessions the app needs before it reads a trend."
        case .noRecentSession:
            text = "Nothing in the last 7 days belongs to this analysis, so its figures describe a break "
                + "rather than a training week."
        case .noStrengthDomain:
            text = "Under \(evidence.analysisProfile.displayName) the app has no estimated 1RM to read a "
                + "trend from — that figure exists for strength only."
        case .plateauUndecidable:
            text = "No exercise here has the "
                + "\(ExerciseProgression.plateauSessionCount + 1) sessions the app needs before it can tell "
                + "a plateau from progress."
        case .restDays, .plateauMajority, .latestIsWindowBest, .noNewBest:
            return nil
        }
        return .note(title: insufficientDataNoteTitle, text: text)
    }

    /// One card, validated: the app's version of it, its downgrade to a note,
    /// or `nil` when it has no text left to show.
    static func validate(_ card: AnalysisCard, against evidence: AnalysisReportEvidence) -> AnalysisReportCard? {
        switch card {
        case let .progression(exercise, _, fromKg, toKg, reasoning):
            // A load in kilograms is a strength figure, so an analysis that
            // was not about strength does not show one (US-15 AC5). In
            // practice such a prompt carried no exercise list either and the
            // card would fail below anyway — stated here so the rule is one
            // line rather than a consequence.
            if !isBlank(reasoning),
               evidence.analysisProfile.covers(.strength),
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
                reasoning: isBlank(reasoning)
                    ? insertedRecoveryReasoning(
                        countingUnanalysedTraining: evidence.recoveryCountsUnanalysedTraining
                    )
                    : reasoning,
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

        case let .metric(label, from, to, unit, reasoning, source):
            if !isBlank(reasoning),
               let valid = metric(
                   label: label,
                   from: from,
                   to: to,
                   unit: unit,
                   reasoning: reasoning,
                   source: source,
                   evidence: evidence
               ) {
                return valid
            }
            return note(title: trimmed(label), text: reasoning)

        case let .interference(_, _, _, reasoning):
            // The model's three counts are ignored, exactly as its
            // suggestedRestHours is: the app counted the week and the card
            // shows what it counted. What the model is checked on is whether
            // there was an interference to write about at all — a week with no
            // endurance session in it has none, whatever the card claims.
            //
            // And whether *this* analysis may talk about it: the card is a
            // statement about both domains at once, so a single-domain profile
            // has no card here. Under "Strength" it would put four running
            // days on a screen that says the running was left out, with no
            // sentence to explain them — the leak the recovery card avoids by
            // saying so in its own reasoning (#185).
            guard !isBlank(reasoning),
                  evidence.analysisProfile.coversBothDomains,
                  evidence.interference.hasBothDomains
            else {
                return note(title: interferenceNoteTitle, text: reasoning)
            }
            return .interference(metrics: evidence.interference, reasoning: reasoning)

        case let .note(title, text):
            guard !isBlank(text) else { return nil }
            return .note(title: title, text: text)
        }
    }

    // MARK: - Metric

    /// The metric card with the app's own current figure, or `nil` when the
    /// week does not back it:
    ///
    /// - the model is allowed to state the unit at all
    ///   (`MetricUnit.isStatableByTheModel`) — a heart rate is not a figure it
    ///   may set a target for, whatever schema a provider actually honoured,
    /// - the unit belongs to a domain this analysis covers — no kilograms
    ///   under "Endurance", no kilometres under "Strength" (US-15 AC5). A unit
    ///   both domains record passes under any profile, and its *anchor* is
    ///   already restricted to the covered sessions,
    /// - the app has a figure for that unit in the last seven days. Without
    ///   one there is nothing to check the card against, and a "from" nobody
    ///   measured is the invented measurement #175 exists to catch,
    /// - `from` is **the same figure** as the app's, at the precision the
    ///   prompt printed it (`MetricUnit.statesTheSameFigure(_:as:)`),
    /// - `to` is a figure the unit can state, differs from the app's, and sits
    ///   within `metricStepShare` of it,
    /// - both figures, and the step between them, have a reading in the unit —
    ///   a card whose delta rounds to nothing is not a recommendation.
    ///
    /// `from` is replaced by the app's figure, as the progression card's
    /// struck-through weight is: what the card states as a measurement is the
    /// cache's, and only the target and the sentence are the model's.
    private static func metric(
        label: String,
        from: Double,
        to: Double,
        unit: MetricUnit,
        reasoning: String,
        source: String,
        evidence: AnalysisReportEvidence
    ) -> AnalysisReportCard? {
        let title = trimmed(label)
        guard !title.isEmpty, unit.isStatableByTheModel else { return nil }
        if let domain = unit.domain, !evidence.analysisProfile.covers(domain) { return nil }
        guard let app = evidence.weeklyMetrics[unit], app > 0, app.isFinite else { return nil }
        guard unit.statesTheSameFigure(from, as: app) else { return nil }
        guard to.isFinite, to > 0 else { return nil }
        let step = to - app
        guard abs(step) > epsilon, abs(step) <= app * metricStepShare + epsilon else { return nil }
        guard unit.display(app) != nil,
              unit.display(to) != nil,
              unit.delta(from: app, to: to) != nil
        else { return nil }
        return .metric(
            label: title,
            from: app,
            to: to,
            unit: unit,
            reasoning: reasoning,
            source: trimmed(source)
        )
    }

    // MARK: - Progression

    /// The progression as the app states it, or `nil` when the cache does not
    /// back it:
    ///
    /// - the exercise is listed in the prompt (trimmed, case-insensitive),
    /// - its listed working weight exists and `fromKg` is within
    ///   `weightToleranceKg` of it,
    /// - `toKg` is above that working weight, by at most the step prompt
    ///   rule 6 allows (#173), see `maxStepKg(for:)`. No share of the working
    ///   weight on top: 60 → 66 kg is no step the prompt offered.
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
        guard toKg > match.workingKg,
              let maxStep = maxStepKg(for: match.exercise),
              toKg - match.workingKg <= maxStep + epsilon
        else { return nil }
        return .progression(
            exercise: match.exercise.title,
            muscleGroup: match.exercise.muscleGroup,
            fromKg: match.workingKg,
            toKg: toKg,
            reasoning: reasoning
        )
    }

    /// The largest load increase prompt rule 6 allows for a listed exercise,
    /// or `nil` when it allows none:
    ///
    /// - a barbell exercise (`AnalysisPromptBuilder.isBarbell(title:)`):
    ///   `minimumStepKg`, even when a larger step is listed,
    /// - any other exercise: the smallest step its line lists,
    /// - any other exercise without a listed step: none — rule 6 progresses
    ///   reps there, so a heavier target is not backed.
    static func maxStepKg(for exercise: ListedExercise) -> Double? {
        if AnalysisPromptBuilder.isBarbell(title: exercise.title) {
            return minimumStepKg
        }
        return exercise.smallestStepKg
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
