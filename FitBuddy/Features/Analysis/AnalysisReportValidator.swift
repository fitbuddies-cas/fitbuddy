import Foundation
import OSLog

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

    /// The barbell step prompt rule 6 names (#173): the granularity a barbell
    /// exercise's range is rounded to, whatever step is listed for it. The
    /// prompt's own constant, so the two cannot drift apart.
    static let minimumStepKg = AnalysisPromptBuilder.minimumStepKg

    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "Analysis")

    /// Cards the result screen shows at most (design 3.4/3.4b/3.5: zero to four).
    static let maxCards = 4

    /// The most reps a rep progression may add at once (#234): the margin
    /// the 2-for-2 rule wants over the target, so two more reps at the same
    /// weight is exactly the reserve that earns the next load step (ADR-013).
    static let maxRepStep = TwoForTwoCondition.requiredMargin

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

    /// The lead of a report the app turned into a hold verdict because stage 5
    /// capped it on rising effort (`AnalysisVerdictRule.Reason.effortRising`,
    /// product-owner decision on #246). Used under every profile: `holdLead`
    /// speaks of weights, which says nothing to a runner under "Endurance",
    /// and the cap is about effort, not about a missing load step. The
    /// headline stays `holdHeadline`.
    static let effortCapLead =
        "Your recorded effort has risen against your own earlier weeks. Hold your current training before adding more."

    /// The lead of a report the app turned into a progress verdict, because
    /// its own figures carry the step the model argued against (ADR-014 §7).
    ///
    /// Says only what stage 4 measured. ADR-014 spells out the text for the
    /// fourth class but not for this case, so the wording is #227's; it was
    /// kept to the one statement the rule actually read.
    static let progressLead =
        "Your most recent session set the best estimated 1RM of the analysed window on at least one exercise. Read the full analysis below before adding load."

    /// The headline of a report without a verdict (ADR-014 §6). Same string
    /// `AnalysisHeadline` renders, so the stored report and the screen cannot
    /// say different things.
    static let insufficientDataHeadline = AnalysisHeadline.text(for: .insufficientData)

    /// The lead of a report without a verdict, word for word from ADR-014 §6.
    static let insufficientDataLead =
        "Your logged training doesn't yet support a recommendation for or against more load. Keep training as before — the next analysis will have more to go on."

    /// Title of the note that names why there is no verdict (ADR-014 §6).
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
    /// fourth-class verdict must not show (ADR-014 §6/§7). The model's own
    /// choice is kept on the report for #228.
    ///
    /// - Parameters:
    ///   - report: The model's answer, as decoded.
    ///   - evidence: The cache's facts about the window the prompt described.
    static func validate(
        _ report: AnalysisReport,
        against evidence: AnalysisReportEvidence
    ) -> ValidatedAnalysisReport {
        validateLogged(report, against: evidence).report
    }

    /// `validate(_:against:)`, together with the record of every place the
    /// app did not take the answer as sent (US-16 AC4, #228).
    ///
    /// The log is written by the same steps that intervene, never
    /// reconstructed by comparing input and output afterwards: a card that
    /// became a note and one the model sent as a note look alike on the
    /// report, and only the step that downgraded it knows why.
    static func validateLogged(
        _ report: AnalysisReport,
        against evidence: AnalysisReportEvidence
    ) -> (report: ValidatedAnalysisReport, log: AnalysisValidationLog) {
        var interventions: [AnalysisIntervention] = []
        var cards: [TrackedCard] = []
        for card in report.cards {
            let checked = validateLogged(card, against: evidence)
            if let valid = checked.card { cards.append(TrackedCard(card: valid, sentAs: card.kind)) }
            if let intervention = checked.intervention { interventions.append(intervention) }
        }
        let outcome = AnalysisVerdictRule.outcome(for: evidence)
        let verdict = outcome.verdict
        var headline = report.headline
        var lead = report.lead

        // US-3 AC6 / US-14 AC4 / US-15 AC3: at 6 of 7 days no progression is
        // shown without the recovery hint. The count spans every source and
        // both domains since #184, so four strength sessions and two runs on
        // six days trigger the hint just as six strength sessions do. A model
        // recovery card always survives at that count, so a missing one means
        // the model left it out. This is the card side of ADR-014 stage 0;
        // the verdict side is in the rule.
        if evidence.recovery.needsRecovery, !cards.contains(where: { $0.card.kind == .recovery }) {
            let inserted = AnalysisReportCard.recovery(
                reasoning: insertedRecoveryReasoning(
                    countingUnanalysedTraining: evidence.recoveryCountsUnanalysedTraining
                ),
                metrics: evidence.recovery
            )
            cards.insert(TrackedCard(card: inserted, sentAs: .recovery), at: 0)
            interventions.append(
                AnalysisIntervention(subject: .recovery, action: .inserted, reason: .recoveryMissing)
            )
        }

        // ADR-014 §6: without a verdict there is no card that would be one.
        // A load or rep progression *is* a verdict, a recovery card is
        // `recover` under another name, and a metric card states a step
        // nobody backed. They are downgraded to notes rather than dropped, as
        // everywhere else in this file — the user paid for the sentence.
        // Above them goes the app's own note naming the condition that fired.
        // The card checks of ADR-013 run first and are untouched by this:
        // a card they struck is already a note (ADR-014 §7).
        if verdict == .insufficientData {
            cards = cards.compactMap { tracked in
                let demoted = withoutAVerdict(tracked.card)
                if demoted != tracked.card {
                    interventions.append(AnalysisIntervention(
                        subject: AnalysisInterventionSubject(tracked.card.kind),
                        action: demoted == nil ? .dropped : .downgraded,
                        reason: .noVerdict
                    ))
                }
                return demoted.map { TrackedCard(card: $0, sentAs: tracked.sentAs) }
            }
            if let note = insufficientDataNote(reason: outcome.reason, evidence: evidence) {
                cards.insert(TrackedCard(card: note, sentAs: .note), at: 0)
            }
        }

        // A cut card is logged under the kind the model sent it as: a
        // progression already downgraded to a note reads "progression
        // dropped", not like a note the model wrote itself.
        let capped = capped(cards)
        let kept = capped.kept.map(\.card)
        interventions += capped.dropped.map {
            AnalysisIntervention(subject: AnalysisInterventionSubject($0.sentAs), action: .dropped, reason: .overCardLimit)
        }

        // Where the app's verdict differs from the model's, the model's
        // headline and lead argue for the call the app has just replaced, so
        // they go with it (ADR-014 §7). Where the two agree, the model keeps
        // its wording — the app overruled nothing in it.
        if verdict != report.verdict {
            interventions.append(
                AnalysisIntervention(subject: .verdict, action: .replaced, reason: .verdictOverridden)
            )
            headline = AnalysisHeadline.text(for: verdict)
            lead = self.lead(for: verdict, reason: outcome.reason, evidence: evidence)
            if headline != report.headline {
                interventions.append(
                    AnalysisIntervention(subject: .headline, action: .replaced, reason: .verdictOverridden)
                )
            }
            if lead != report.lead {
                interventions.append(
                    AnalysisIntervention(subject: .lead, action: .replaced, reason: .verdictOverridden)
                )
            }
        }

        // #170, kept after #227 took the verdict away from the cards: a
        // progress lead may only name a step that survived. The verdict is
        // the app's either way — what this guards is the model's prose, which
        // is otherwise taken on trust wherever the two happen to agree. A
        // lead reading "Bench press can go up to 100 kg." over a progression
        // the cache rejected states a figure the app has just thrown away.
        // `progressLead` then says what stage 4 measured and nothing else.
        if verdict == .progress, !kept.contains(where: \.backsProgress) {
            // Logged only where the model's own lead was still standing —
            // an overridden verdict already replaced it above.
            if lead == report.lead, lead != progressLead {
                interventions.append(
                    AnalysisIntervention(subject: .lead, action: .replaced, reason: .noBackingCard)
                )
            }
            lead = progressLead
        }

        let validated = ValidatedAnalysisReport(
            headline: headline,
            verdict: verdict,
            lead: lead,
            cards: kept,
            summary: report.summary,
            modelVerdict: report.verdict
        )
        let log = AnalysisValidationLog(
            modelVerdict: report.verdict,
            appVerdict: verdict,
            verdictReason: outcome.reason,
            interventions: interventions
        )
        return (validated, log)
    }

    /// The app's lead for a verdict it put over the model's (ADR-014 §7).
    /// A hold from the effort cap gets `effortCapLead`, every other hold
    /// `holdLead`.
    static func lead(
        for verdict: AnalysisVerdict,
        reason: AnalysisVerdictRule.Reason,
        evidence: AnalysisReportEvidence
    ) -> String {
        switch verdict {
        case .progress: return progressLead
        case .recover: return recoveryLead(trainingDays: evidence.recovery.trainingDays)
        case .hold: return reason == .effortRising ? effortCapLead : holdLead
        case .insufficientData: return insufficientDataLead
        }
    }

    /// A validated card with whatever made it a verdict taken out of it, for
    /// an `insufficientData` report (ADR-014 §6).
    ///
    /// Progression, rep progression, recovery and metric cards become notes:
    /// the first two name a step, the recovery card is a verdict of its own,
    /// and a metric card's `to` is a step too. Imbalance and interference
    /// cards stay: every figure on them is one the app measured and
    /// replaced, and neither argues for or against load.
    private static func withoutAVerdict(_ card: AnalysisReportCard) -> AnalysisReportCard? {
        switch card {
        case let .progression(exercise, _, _, _, reasoning),
             let .repProgression(exercise, _, _, _, _, reasoning):
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
    /// naming the condition that fired (ADR-014 §6).
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
        case .restDays, .plateauMajority, .latestIsWindowBest, .noNewBest, .effortRising:
            return nil
        }
        return .note(title: insufficientDataNoteTitle, text: text)
    }

    /// One card, validated: the app's version of it, its downgrade to a note,
    /// or `nil` when it has no text left to show.
    static func validate(_ card: AnalysisCard, against evidence: AnalysisReportEvidence) -> AnalysisReportCard? {
        validateLogged(card, against: evidence).card
    }

    /// One card, validated, and the intervention it took — `nil` when the
    /// card went through as sent (#228).
    static func validateLogged(
        _ card: AnalysisCard,
        against evidence: AnalysisReportEvidence
    ) -> (card: AnalysisReportCard?, intervention: AnalysisIntervention?) {
        switch card {
        case let .progression(exercise, _, fromKg, toKg, reasoning):
            let title = trimmed(exercise)
            guard !isBlank(reasoning) else {
                return downgraded(.progression, title: title, text: reasoning, reason: .blankText)
            }
            // A load in kilograms is a strength figure, so an analysis that
            // was not about strength does not show one (US-15 AC5). In
            // practice such a prompt carried no exercise list either and the
            // card would fail below anyway — stated here so the rule is one
            // line rather than a consequence.
            guard evidence.analysisProfile.covers(.strength) else {
                return downgraded(.progression, title: title, text: reasoning, reason: .domainNotCovered)
            }
            let check = checkProgression(
                exercise: exercise,
                fromKg: fromKg,
                toKg: toKg,
                reasoning: reasoning,
                listed: evidence.exercises
            )
            switch check {
            case let .accepted(valid):
                return (valid, nil)
            case let .rejected(rejection, figure):
                // The title and the figures are the user's training data.
                logger.notice(
                    "Progression card rejected (\(rejection.rawValue, privacy: .public)): \(exercise, privacy: .private) \(fromKg, privacy: .private) → \(toKg, privacy: .private) kg"
                )
                return downgraded(
                    .progression,
                    title: title,
                    text: reasoning,
                    reason: AnalysisInterventionReason(rejection),
                    figure: figure
                )
            }

        case let .repProgression(exercise, _, weightKg, fromReps, toReps, reasoning):
            // A strength card like the load progression (US-15 AC5), checked
            // against the same listed exercises (#234).
            let title = trimmed(exercise)
            guard !isBlank(reasoning) else {
                return downgraded(.repProgression, title: title, text: reasoning, reason: .blankText)
            }
            guard evidence.analysisProfile.covers(.strength) else {
                return downgraded(.repProgression, title: title, text: reasoning, reason: .domainNotCovered)
            }
            let check = checkRepProgression(
                exercise: exercise,
                weightKg: weightKg,
                fromReps: fromReps,
                toReps: toReps,
                reasoning: reasoning,
                listed: evidence.exercises
            )
            switch check {
            case let .accepted(valid):
                return (valid, nil)
            case let .rejected(rejection, figure):
                return downgraded(
                    .repProgression,
                    title: title,
                    text: reasoning,
                    reason: AnalysisInterventionReason(rejection),
                    figure: figure
                )
            }

        case let .recovery(reasoning, _):
            // Kept only when the app's own count calls for recovery. The issue
            // also accepts "the model explains it", but the schema forces a
            // reasoning onto every card, so that condition would keep every
            // recovery card — "0 sessions / 7 days" after a break included.
            // The model's suggestedRestHours is ignored: every figure on the
            // card is the app's.
            guard evidence.recovery.needsRecovery else {
                return downgraded(.recovery, title: recoveryNoteTitle, text: reasoning, reason: .recoveryNotNeeded)
            }
            guard !isBlank(reasoning) else {
                let completed = AnalysisReportCard.recovery(
                    reasoning: insertedRecoveryReasoning(
                        countingUnanalysedTraining: evidence.recoveryCountsUnanalysedTraining
                    ),
                    metrics: evidence.recovery
                )
                return (completed, AnalysisIntervention(subject: .recovery, action: .replaced, reason: .blankText))
            }
            return (.recovery(reasoning: reasoning, metrics: evidence.recovery), nil)

        case let .imbalance(groupA, perWeekA, groupB, perWeekB, reasoning):
            guard !isBlank(reasoning) else {
                return downgraded(.imbalance, title: fallbackNoteTitle, text: reasoning, reason: .blankText)
            }
            let check = imbalance(
                groupA: groupA,
                perWeekA: perWeekA,
                groupB: groupB,
                perWeekB: perWeekB,
                reasoning: reasoning,
                frequencies: evidence.muscleGroupsPerWeek
            )
            switch check {
            case let .accepted(valid):
                return (valid, nil)
            case let .rejected(reason, figure):
                return downgraded(.imbalance, title: fallbackNoteTitle, text: reasoning, reason: reason, figure: figure)
            }

        case let .metric(label, from, to, unit, reasoning, source):
            let title = trimmed(label)
            guard !isBlank(reasoning) else {
                return downgraded(.metric, title: title, text: reasoning, reason: .blankText)
            }
            let check = metric(
                label: label,
                from: from,
                to: to,
                unit: unit,
                reasoning: reasoning,
                source: source,
                evidence: evidence
            )
            switch check {
            case let .accepted(valid):
                return (valid, nil)
            case let .rejected(reason, figure):
                return downgraded(.metric, title: title, text: reasoning, reason: reason, figure: figure)
            }

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
            guard !isBlank(reasoning) else {
                return downgraded(.interference, title: interferenceNoteTitle, text: reasoning, reason: .blankText)
            }
            guard evidence.analysisProfile.coversBothDomains else {
                return downgraded(
                    .interference, title: interferenceNoteTitle, text: reasoning, reason: .domainNotCovered
                )
            }
            guard evidence.interference.hasBothDomains else {
                return downgraded(
                    .interference, title: interferenceNoteTitle, text: reasoning, reason: .noInterference
                )
            }
            return (.interference(metrics: evidence.interference, reasoning: reasoning), nil)

        case let .note(title, text):
            guard !isBlank(text) else {
                return (nil, AnalysisIntervention(subject: .note, action: .dropped, reason: .blankText))
            }
            return (.note(title: title, text: text), nil)
        }
    }

    /// A failed card as a note — or dropped, when it has no text — and the
    /// intervention that says which of the two happened and why.
    private static func downgraded(
        _ kind: AnalysisCard.Kind,
        title: String,
        text: String,
        reason: AnalysisInterventionReason,
        figure: AnalysisInterventionFigure? = nil
    ) -> (card: AnalysisReportCard?, intervention: AnalysisIntervention?) {
        let card = note(title: title, text: text)
        let intervention = AnalysisIntervention(
            subject: AnalysisInterventionSubject(kind),
            action: card == nil ? .dropped : .downgraded,
            reason: reason,
            figure: figure
        )
        return (card, intervention)
    }

    // MARK: - Metric

    /// The metric card with the app's own current figure, or the reason the
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
    ) -> CardCheck {
        let title = trimmed(label)
        let figureUnit = AnalysisFigureUnit(unit)
        guard !title.isEmpty else { return .rejected(.missingLabel, nil) }
        guard unit.isStatableByTheModel else { return .rejected(.unitNotStatable, nil) }
        if let domain = unit.domain, !evidence.analysisProfile.covers(domain) {
            return .rejected(.domainNotCovered, nil)
        }
        guard let app = evidence.weeklyMetrics[unit], app > 0, app.isFinite else {
            return .rejected(.noAppFigure, AnalysisInterventionFigure(proposed: from, unit: figureUnit))
        }
        guard unit.statesTheSameFigure(from, as: app) else {
            return .rejected(.wrongStartingFigure, AnalysisInterventionFigure(proposed: from, app: app, unit: figureUnit))
        }
        guard to.isFinite, to > 0 else { return .rejected(.unreadableFigure, nil) }
        let step = to - app
        guard abs(step) > epsilon, abs(step) <= app * metricStepShare + epsilon else {
            return .rejected(.stepOutOfRange, AnalysisInterventionFigure(
                proposed: to,
                app: app,
                allowed: app * (1 - metricStepShare)...app * (1 + metricStepShare),
                unit: figureUnit
            ))
        }
        guard unit.display(app) != nil,
              unit.display(to) != nil,
              unit.delta(from: app, to: to) != nil
        else {
            return .rejected(.unreadableFigure, AnalysisInterventionFigure(proposed: to, app: app, unit: figureUnit))
        }
        return .accepted(.metric(
            label: title,
            from: app,
            to: to,
            unit: unit,
            reasoning: reasoning,
            source: trimmed(source)
        ))
    }

    // MARK: - Progression

    /// Why a progression card was not backed (#233).
    ///
    /// Each case is one line in the log, so the rate of each reason can be
    /// read over live runs (#228, #229): a window in which most cards fail as
    /// `conditionNotCheckable` is a window of users without routines — a
    /// finding for ADR-013, not a model problem. `belowRange` is kept apart
    /// from `aboveRange` for the same reason: too cautious is a finding too.
    enum ProgressionRejection: String, Equatable, Sendable {
        /// No listed exercise carries the card's title.
        case notListed
        /// The listed exercise has no working weight a load change could
        /// start from — a bodyweight movement.
        case noWorkingWeight
        /// `fromKg` is not the working weight the prompt named.
        case wrongStartingWeight
        /// `toKg` is at or under the working weight.
        case noIncrease
        /// The 2-for-2 rule is not met: no load increase is on (ADR-013).
        case conditionNotMet
        /// The 2-for-2 rule could not be applied for want of a rep target —
        /// not the same as met (ADR-013).
        case conditionNotCheckable
        /// The rule is met, but the exercise has no step to move by: reps are
        /// the lever there (#234).
        case noLoadStep
        /// `toKg` is above the working weight but under one step: not a load
        /// the equipment offers.
        case belowRange
        /// `toKg` is over the ceiling of `ProgressionBand`.
        case aboveRange
        /// `toKg` is inside the range but not on a step the equipment offers
        /// — 64 kg on a 2.5 kg bar — beyond the rounding `weightToleranceKg`
        /// forgives.
        case offStep
        /// A rep progression's `fromReps` is not the reps the prompt listed
        /// with the working weight (#234).
        case wrongStartingReps
        /// A rep progression adds more than `maxRepStep` reps at once (#234).
        case aboveRepStep
    }

    /// The outcome of checking a progression card against the listed
    /// exercises.
    enum ProgressionCheck: Equatable, Sendable {
        case accepted(AnalysisReportCard)
        /// The reason, with the model's figure next to the app's that the
        /// failed step compared (#228). Built where the check looked the
        /// exercise up, so the log never repeats the lookup.
        case rejected(ProgressionRejection, AnalysisInterventionFigure)
    }

    /// The outcome of a card check that can fail for more than one reason,
    /// with the figure the log records next to it (#228).
    enum CardCheck: Equatable, Sendable {
        case accepted(AnalysisReportCard)
        case rejected(AnalysisInterventionReason, AnalysisInterventionFigure?)
    }

    /// Checks a progression card against the listed exercises (#175, #233):
    ///
    /// - the exercise is listed in the prompt (trimmed, case-insensitive),
    /// - its listed working weight exists and `fromKg` is within
    ///   `weightToleranceKg` of it,
    /// - `toKg` is above that working weight,
    /// - the 2-for-2 rule is **met** for the exercise (ADR-013): not met and
    ///   not checkable both reject, since a load increase is not on either
    ///   way — the card falls back to a note, and to rep progression once
    ///   #234 lands,
    /// - the exercise has a step to move by, and `toKg` lies within
    ///   `ProgressionBand.range(for:)` — the range the prompt line named,
    ///   both ends inclusive. 60 → 66 kg on a bench at 60 is over the 10 %
    ///   ceiling; 60 → 61 kg is under the one step the bar can take,
    /// - `toKg` sits on a step: a whole number of steps above the working
    ///   weight, within `weightToleranceKg` — the same rounding `fromKg` is
    ///   forgiven. 64 kg on a 2.5 kg bar is a weight nobody can load, and a
    ///   card must not show one. The range is checked on the model's figure
    ///   first, so 66 kg reads as over the ceiling rather than as off the
    ///   step, and 62 kg as a rounding of 62.5 rather than as under it.
    ///
    /// Title, muscle group and `fromKg` are replaced by the listed values, so
    /// the struck-through figure on the card is the cache's, not the model's
    /// rounding of it; `toKg` is the model's choice of step, snapped to the
    /// step itself (62 for 62.5 reads 62.5 kg), because every figure a card
    /// states as a load is one the equipment offers. Where two listed
    /// exercises share a title, the first whose weight matches wins.
    static func checkProgression(
        exercise: String,
        fromKg: Double,
        toKg: Double,
        reasoning: String,
        listed: [ListedExercise]
    ) -> ProgressionCheck {
        let name = folded(exercise)
        let candidates = listed.filter { folded($0.title) == name }
        let unmatched = AnalysisInterventionFigure(proposed: toKg, unit: .kilograms)
        guard !candidates.isEmpty else { return .rejected(.notListed, unmatched) }
        guard candidates.contains(where: { $0.workingSet != nil }) else {
            return .rejected(.noWorkingWeight, unmatched)
        }
        let match = candidates.lazy
            .compactMap { listed -> (exercise: ListedExercise, workingKg: Double)? in
                guard let working = listed.workingSet?.roundedWeightKg,
                      abs(fromKg - working) <= weightToleranceKg + epsilon
                else { return nil }
                return (listed, working)
            }
            .first
        guard let match else {
            return .rejected(.wrongStartingWeight, startingWeightFigure(proposed: fromKg, candidates: candidates))
        }
        let againstWorking = AnalysisInterventionFigure(proposed: toKg, app: match.workingKg, unit: .kilograms)
        guard toKg > match.workingKg + epsilon else { return .rejected(.noIncrease, againstWorking) }
        switch match.exercise.twoForTwo {
        case .notMet: return .rejected(.conditionNotMet, againstWorking)
        case .notCheckable: return .rejected(.conditionNotCheckable, againstWorking)
        case .met: break
        }
        guard let step = ProgressionBand.stepKg(for: match.exercise),
              let range = ProgressionBand.range(for: match.exercise)
        else { return .rejected(.noLoadStep, againstWorking) }
        let againstRange = AnalysisInterventionFigure(
            proposed: toKg, app: match.workingKg, allowed: range, unit: .kilograms
        )
        guard toKg >= range.lowerBound - weightToleranceKg - epsilon else {
            return .rejected(.belowRange, againstRange)
        }
        guard toKg <= range.upperBound + weightToleranceKg + epsilon else {
            return .rejected(.aboveRange, againstRange)
        }
        let steps = ((toKg - match.workingKg) / step).rounded()
        let onStep = PlainWeightFormatter.rounded(match.workingKg + steps * step)
        guard abs(toKg - onStep) <= weightToleranceKg + epsilon else { return .rejected(.offStep, againstRange) }
        return .accepted(.progression(
            exercise: match.exercise.title,
            muscleGroup: match.exercise.muscleGroup,
            fromKg: match.workingKg,
            toKg: onStep,
            reasoning: reasoning
        ))
    }

    // MARK: - Rep progression (#234)

    /// Checks a rep progression card against the listed exercises, by the
    /// same rule as the load one: the exercise is listed, `weightKg` is its
    /// working weight (within `weightToleranceKg`), `fromReps` is the reps the
    /// prompt listed with it, and `toReps` adds between one and `maxRepStep`
    /// reps.
    ///
    /// **Not gated on the 2-for-2 rule.** The card exists for the exercises
    /// the rule holds back — not met, not checkable, no load step — and it is
    /// harmless where the rule is met: more reps at the same weight is never
    /// a load the log does not back. Title, muscle group, weight and starting
    /// reps are replaced by the listed values; `toReps` stays the model's.
    static func checkRepProgression(
        exercise: String,
        weightKg: Double,
        fromReps: Int,
        toReps: Int,
        reasoning: String,
        listed: [ListedExercise]
    ) -> ProgressionCheck {
        let name = folded(exercise)
        let candidates = listed.filter { folded($0.title) == name }
        let unmatched = AnalysisInterventionFigure(proposed: Double(toReps), unit: .repetitions)
        guard !candidates.isEmpty else { return .rejected(.notListed, unmatched) }
        guard candidates.contains(where: { $0.workingSet != nil }) else {
            return .rejected(.noWorkingWeight, unmatched)
        }
        let match = candidates.lazy
            .compactMap { listed -> (exercise: ListedExercise, working: WorkingSet)? in
                guard let working = listed.workingSet,
                      abs(weightKg - working.roundedWeightKg) <= weightToleranceKg + epsilon
                else { return nil }
                return (listed, working)
            }
            .first
        guard let match else {
            return .rejected(.wrongStartingWeight, startingWeightFigure(proposed: weightKg, candidates: candidates))
        }
        let reps = match.working.reps
        guard fromReps == reps else {
            return .rejected(
                .wrongStartingReps,
                AnalysisInterventionFigure(proposed: Double(fromReps), app: Double(reps), unit: .repetitions)
            )
        }
        let againstStep = AnalysisInterventionFigure(
            proposed: Double(toReps),
            app: Double(reps),
            allowed: Double(reps + 1)...Double(reps + maxRepStep),
            unit: .repetitions
        )
        guard toReps > fromReps else { return .rejected(.noIncrease, againstStep) }
        guard toReps - fromReps <= maxRepStep else { return .rejected(.aboveRepStep, againstStep) }
        return .accepted(.repProgression(
            exercise: match.exercise.title,
            muscleGroup: match.exercise.muscleGroup,
            weightKg: match.working.roundedWeightKg,
            fromReps: match.working.reps,
            toReps: toReps,
            reasoning: reasoning
        ))
    }

    /// The model's starting weight next to the first weight the prompt
    /// listed under the title, for a card that matched none of them (#228).
    private static func startingWeightFigure(
        proposed: Double,
        candidates: [ListedExercise]
    ) -> AnalysisInterventionFigure {
        let listedWeight = candidates.lazy.compactMap { $0.workingSet?.roundedWeightKg }.first
        return AnalysisInterventionFigure(proposed: proposed, app: listedWeight, unit: .kilograms)
    }

    // MARK: - Imbalance

    /// The imbalance with the app's figures, or the reason the cache does not
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
    ) -> CardCheck {
        guard let a = MuscleGroup(rawValue: folded(groupA)),
              let b = MuscleGroup(rawValue: folded(groupB)),
              a != b, a != .other, b != .other
        else { return .rejected(.unknownMuscleGroup, nil) }
        let appA = frequencies[a] ?? 0
        let appB = frequencies[b] ?? 0
        guard matchesFrequency(perWeekA, appA) else {
            return .rejected(.frequencyMismatch, AnalysisInterventionFigure(proposed: perWeekA, app: appA, unit: .sessionsPerWeek))
        }
        guard matchesFrequency(perWeekB, appB) else {
            return .rejected(.frequencyMismatch, AnalysisInterventionFigure(proposed: perWeekB, app: appB, unit: .sessionsPerWeek))
        }
        guard !matchesFrequency(appA, appB) else { return .rejected(.noImbalance, nil) }
        return .accepted(.imbalance(groupA: a, perWeekA: appA, groupB: b, perWeekB: appB, reasoning: reasoning))
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
    ///
    /// Returns the cut cards too, in the order they were cut, so the log can
    /// name them (#228).
    private static func capped(
        _ cards: [TrackedCard]
    ) -> (kept: [TrackedCard], dropped: [TrackedCard]) {
        var cards = cards
        var dropped: [TrackedCard] = []
        while cards.count > maxCards {
            let index = cards.lastIndex { $0.card.kind == .note }
                ?? cards.lastIndex { $0.card.kind != .recovery }
                ?? cards.count - 1
            dropped.append(cards.remove(at: index))
        }
        return (cards, dropped)
    }

    /// A card on its way through `validateLogged(_:against:)`, with the kind
    /// the model sent it as — a note after a downgrade still remembers it was
    /// a progression, so the cap can log it as one (#228). A card the app
    /// added itself counts as sent as its own kind.
    private struct TrackedCard {
        let card: AnalysisReportCard
        let sentAs: AnalysisCard.Kind
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
