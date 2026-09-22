import Foundation

/// Turns the cached workout window into the prompt pair `InferenceService`
/// sends to Claude (US-3, #30).
///
/// Everything the model sees comes from this one user's own cache. There are
/// no population averages, strength standards or "typical" volumes anywhere in
/// the output, and the system prompt forbids inventing them — US-3 AC3 is a
/// property of the prompt, not of the model's goodwill.
///
/// Since #183 the user turn is built from domain sections rather than from one
/// strength narrative: `StrengthPromptSection`, `EndurancePromptSection` and
/// `LoadPromptSection`, each rendered only where the window holds data for it.
/// Which section a session lands in is decided by `AnalysisDomain`, i.e. by
/// the normalized sport of ADR-012 — a Strava `WeightTraining` session is
/// strength work, and a Hevy session of treadmill sets is not.
///
/// Since #185 the user's `AnalysisProfile` decides which of those sections are
/// built at all. `.overallLoad` builds everything the window holds, which is
/// the prompt as #183 and #184 left it; the two single-domain profiles keep
/// the other half out of the figures and say so, so the model never reads a
/// deliberate omission as an absence of training.
enum AnalysisPromptBuilder {
    /// Sessions listed individually. Four weeks of training fits comfortably,
    /// and even a widened 13-week window rarely fills it; the cap only guards
    /// the tail, where sessions add tokens but no signal — the aggregates
    /// above already carry the older ones.
    static let maxListedSessions = 30

    /// Exercises listed individually in the Exercises section (#173).
    ///
    /// Ten because the section exists for the recommendation, and a
    /// recommendation for the next block names a handful of lifts, not a
    /// whole programme. Ranked by volume, so the lifts the window was built
    /// around come first; every exercise past the cap costs a line of tokens
    /// for a movement the model would hardly recommend on. The prompt names
    /// the cap, so a missing exercise reads as omitted, not as untrained.
    static let maxListedExercises = 10

    /// The largest logged step still offered as an increment, as a share of
    /// the latest working weight (#173).
    ///
    /// The gap between two logged weights is only an increment when it is a
    /// small one: 8 and 12 kg dumbbells are two different exercises' worth of
    /// load, not a 4 kg step — that would be +33 % in one session. Past this
    /// share, and past `minimumStepKg`, the step is left out, and rule 6
    /// falls back to reps.
    static let maxStepShare = 0.10

    /// The step that is always an increment, whatever the share (#173).
    ///
    /// `maxStepShare` alone was chosen with barbell weights in mind: on a
    /// 10 kg lateral raise it would drop the 2 kg step the rack actually
    /// offers and push rule 6 to reps. Up to one plate pair a logged step is
    /// kept — the same 2.5 kg the report validation allows a barbell
    /// exercise (#175) — while
    /// 8 → 12 kg dumbbells stay a change of equipment.
    static let minimumStepKg = 2.5

    /// Builds the prompt pair from the cached window.
    ///
    /// - Parameters:
    ///   - summaries: Cached workouts, in any order. Anything outside the two
    ///     analysis windows is ignored, so the dashboard's 90-day read can be
    ///     passed in unchanged. Endurance sessions are no longer dropped
    ///     (#183): they are described by `EndurancePromptSection` instead.
    ///   - exercises: The movements of the analysed window, rolled up per
    ///     exercise (`exerciseSummaries(since:)` with the window's start). The
    ///     prompt lists the top `maxListedExercises` of them by volume.
    ///   - progressions: The progression of each listed movement, keyed by
    ///     `ExerciseSummary.id`. Sessions before the window's start are
    ///     ignored, so a wider read changes nothing. A listed movement without
    ///     an entry is skipped rather than described from its totals alone.
    ///   - window: The window actually analysed — the default, or a wider rung
    ///     of the fallback ladder when the last four weeks are empty (#87).
    ///   - now: Injectable clock, so the windows are testable.
    ///   - calendar: Decides where a day starts, so training days follow the
    ///     user's time zone.
    ///   - profile: What the user said they train for (US-13). An empty
    ///     profile — the default, and every install that never answered —
    ///     leaves the prompt byte-for-byte as it was without one.
    ///   - analysisProfile: What this run is about (US-15 AC1, #185). Decides
    ///     which domain sections are built at all. `.overallLoad` — the
    ///     default — is "everything the window holds", i.e. exactly the prompt
    ///     of #183 and #184, so no call site that does not care has to say so.
    static func make(
        summaries: [WorkoutSummary],
        exercises: [ExerciseSummary] = [],
        progressions: [String: ExerciseProgression] = [:],
        window: AnalysisWindow = .default,
        now: Date = Date(),
        calendar: Calendar = .current,
        profile: TrainingProfile = TrainingProfile(),
        analysisProfile: AnalysisProfile = .overallLoad
    ) -> AnalysisPrompt {
        AnalysisPrompt(
            system: systemPrompt,
            user: userPrompt(
                summaries: summaries,
                exercises: exercises,
                progressions: progressions,
                window: window,
                now: now,
                calendar: calendar,
                profile: profile,
                analysisProfile: analysisProfile
            )
        )
    }

    // MARK: - Profile

    /// The user's own answers, as facts about them (US-13 AC3, #192) — or
    /// nothing at all.
    ///
    /// `nil` rather than a heading with nothing under it: "Profile: —" reads
    /// to the model as a statement about the person, and a half profile
    /// states only the half that was answered.
    ///
    /// The closing line is the one that matters most. It names what the data
    /// below actually covers, so a goal that asks for context the prompt does
    /// not carry — "improve endurance" over a cache of bench sessions — is
    /// answered here rather than left to rule 3. Since #183 the prompt can
    /// carry endurance work, so the line says which domains are in it instead
    /// of claiming strength only.
    ///
    /// - Parameter domains: The domains the prompt actually carries a section
    ///   for — what the profile covers, narrowed to what the window holds
    ///   (#185). An empty window reads as strength-only, which is what it said
    ///   before there was anything else to say.
    static func profileSection(
        _ profile: TrainingProfile,
        covering domains: [AnalysisDomain] = [.strength]
    ) -> String? {
        var lines: [String] = []
        if let goal = profile.goal {
            lines.append("Goal: \(goal.displayName.lowercased())")
        }
        if let experience = profile.experience {
            lines.append("Strength training experience: \(experience.displayName.lowercased())")
        }
        guard !lines.isEmpty else { return nil }
        let covered: String
        if domains.contains(.strength) && domains.contains(.endurance) {
            covered = "my strength and endurance sessions"
        } else if domains == [.endurance] {
            covered = "my endurance sessions only"
        } else {
            covered = "my strength sessions only"
        }
        lines.append(
            "The data below covers \(covered); do not assume anything "
                + "about other training I may do."
        )
        return (["## Profile"] + lines).joined(separator: "\n")
    }

    /// The sessions of one domain (#183).
    ///
    /// The filter reads `AnalysisDomain(summary:)`, i.e. the normalized sport
    /// (`WorkoutSummary.isEnduranceWork`, ADR-012), and no longer the source. Before
    /// #183 it dropped every endurance *source* — which put a Strava
    /// `WeightTraining` session out of the prompt entirely and would have let
    /// a Hevy treadmill session into the strength figures as "1 exercise,
    /// 1 working set, 0 kg", exactly the reading of rule 5 that the filter
    /// existed to prevent. The sport is what the two sections are about, so
    /// the sport is what selects them.
    ///
    /// Which of these sections the user's `AnalysisProfile` asks for is a
    /// second, separate question, answered by `AnalysisProfile.covers(_:)`
    /// where the sections are assembled (#185). Deliberately not a second
    /// overload of this method: `sessions(in:for: .strength)` would then be
    /// ambiguous at every call site that spells the case with a leading dot.
    static func sessions(in summaries: [WorkoutSummary], for domain: AnalysisDomain) -> [WorkoutSummary] {
        summaries.filter { AnalysisDomain(summary: $0) == domain }
    }

    /// The strength sessions of the analysed window — what every figure about
    /// the recent window is computed over, in the prompt and in the check of
    /// the model's answer against it (#175).
    static func analysedSessions(
        in summaries: [WorkoutSummary],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> [WorkoutSummary] {
        let start = window.start(endingAt: now, calendar: calendar)
        return sessions(in: summaries, for: .strength).filter { $0.startTime >= start }
    }

    /// The movements the Exercises section lists: the top
    /// `maxListedExercises` by volume in the window (#173).
    ///
    /// Public to the feature so `AnalysisViewModel` reads progressions for
    /// exactly these and no others. Ties are broken by session count, then by
    /// title, so the same cache always yields the same prompt — and
    /// bodyweight movements, which carry no kilograms, still rank by how often
    /// they were trained.
    static func promptedExercises(from exercises: [ExerciseSummary]) -> [ExerciseSummary] {
        let ranked = exercises.sorted { lhs, rhs in
            if lhs.volumeKg != rhs.volumeKg { return lhs.volumeKg > rhs.volumeKg }
            if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
            return lhs.title < rhs.title
        }
        return Array(ranked.prefix(maxListedExercises))
    }

    // MARK: - System

    /// The ground rules. Spelled out rather than implied: the model has no way
    /// to know that FitBuddy is not a medical product, that the muscle split is
    /// a keyword heuristic, or that bodyweight work carries load without
    /// kilograms — and each of those, unstated, produces confident nonsense.
    ///
    /// Since #183 the rules are scoped per domain. Rule 5 — the kilogram rule —
    /// is the one that made endurance sessions unsafe to pass through at all,
    /// so it now says which sections it applies to, and rule 7 states the
    /// endurance counterpart. Rule 2 was sharpened at the same time: general
    /// training principles are allowed and named as such, while population
    /// comparisons and norm values stay forbidden (US-3 AC3, US-15 AC6).
    static let systemPrompt = """
    You are FitBuddy's training assistant. You analyse one person's own \
    training history — strength work, endurance work, or both — and give them \
    a concrete recommendation for their next training block.

    The data comes in sections. A section you were not given covers training \
    this person did not record in this window, or training they chose to \
    leave out of this analysis: either way, do not reason about it and do not \
    fill it in.

    Ground rules:

    1. FitBuddy is not a medical product. Do not diagnose, and do not give \
    medical, nutritional or rehabilitation advice. Do not interpret pain, \
    injury or symptoms. If the data points at something health-related, say \
    plainly that this is outside what FitBuddy can assess and that a \
    qualified professional is the right address.

    2. Judge this data only against itself. The person's own history is the \
    only reference point you have: compare the recent window with the \
    previous one and name what these numbers show. General training \
    principles — progressive overload, spreading intensity across the week, \
    recovery after hard days — are established practice, and you may name \
    them as principles and apply them to these numbers. Never invoke \
    population averages, strength standards, "typical" volumes for a body \
    weight, sex or age, or any benchmark from outside this prompt. You were \
    given none, and inventing one would present a guess as a fact.

    3. Work only with what is stated. Do not assume a training goal, training \
    age, body weight, equipment or weekly schedule that is not in the data. \
    Where a recommendation would depend on something you were not told, say \
    what you would need to know instead of filling the gap.

    4. Muscle groups are classified heuristically from exercise names and are \
    sometimes wrong. Treat the split as an indication, not a measurement.

    5. In the strength sections, volume is the sum of weight x reps over \
    working sets; warm-up sets are excluded. Bodyweight and time-based work \
    contributes sets but no kilograms, so a group can carry real training \
    load while showing little or no volume. Never read a low kg figure as \
    "untrained" on its own. A session listed as "no sets logged" recorded no \
    set data at all, because its source reports whole sessions rather than \
    sets: it is training that happened, its load is not in the volume figures, \
    and it is not bodyweight work — do not explain it as such and do not read \
    its absence from the volume as a light session.

    6. Name only exercises and weights from the Exercises section. Spell an \
    exercise exactly as it is listed there, and start any load change from \
    the weight listed for its most recent session. Never name an exercise \
    that section does not contain, or a weight it does not list as a \
    starting point. A new target weight is always the listed weight of the \
    most recent session plus one step. Increase barbell exercises in steps \
    of 2.5 kg; for every other exercise increase by at most the smallest \
    step listed for it, and where none is listed, progress reps rather than \
    weight.

    7. In the endurance sections, load is distance, time, pace and heart \
    rate. Rule 5 does not apply there: no volume in kilograms is not an \
    absence of training load. Never convert endurance work into kilograms, \
    never judge an endurance session by the strength figures, and never name \
    a kilogram value in a recommendation about endurance training. A figure \
    that is missing — an indoor ride without distance, a session recorded \
    without a heart-rate strap — is unrecorded, not zero. Heart rate is a \
    number this person recorded, never a target: never name a heart-rate \
    zone, a target heart rate, or a percentage of maximum heart rate. Those \
    are derived from population norms, which rule 2 forbids, and you were \
    given neither their maximum heart rate nor the model any zone scheme \
    rests on. Say "easier" or "harder" where you would have named a zone.

    8. The Week structure section is about both domains at once: strength and \
    endurance draw on the same recovery, so training days, days carrying \
    both, and consecutive training days are judged over them together rather \
    than per domain. Its "Last 7 days" line counts a day on which any \
    training was recorded, a run as much as a squat session; six or seven \
    such days are a week without enough rest, whichever domain filled them. \
    Where that section says a domain was left out of this analysis, its \
    sessions still count towards those days and still cost recovery: give \
    your recommendation for the domain that was asked about, and take the day \
    count as it stands rather than recomputing it from the sessions you were \
    shown.

    Answer in English, as one JSON object that follows the response schema:

    - headline: one short sentence stating the verdict.
    - verdict: "progress" when the data supports adding load or reps, \
    "recover" when rest has to come first, "hold" when neither is justified \
    yet.
    - lead: the key takeaway in one to three sentences, at most about 50 \
    words. It must stand on its own: someone who reads only the headline and \
    the lead knows what to do next.
    - summary: the full analysis as plain prose under 200 words, readable \
    without the cards: first what stands out in the data, then a concrete \
    recommendation for the next block.
    - cards: zero to four cards, most important first. Add a card only when \
    the data supports it; when the data is too thin for any, return an empty \
    array — the lead and the summary carry the answer. Use "progression" for \
    a load increase on one exercise: fromKg is the weight listed for its most \
    recent session, toKg the new weight, reasoning one sentence. Use \
    "recovery" when rest comes before any progression, with the rest you \
    recommend in suggestedRestHours. Use "imbalance" when two muscle groups \
    are trained at clearly different frequencies, naming each group and its \
    sessions per week exactly as the Muscle groups section lists them. Use \
    "note" for anything else worth saying, including a rep progression \
    without a weight change and anything about endurance training. Every \
    card follows the ground rules above; a recommendation you cannot ground \
    in the data does not become a card.

    Write the fields in this order.

    Never write placeholder or filler text in any field. A field you have \
    nothing to say in is not a reason to invent something; leave a card out \
    instead.
    """

    // MARK: - User

    private static func userPrompt(
        summaries: [WorkoutSummary],
        exercises: [ExerciseSummary],
        progressions: [String: ExerciseProgression],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar,
        profile: TrainingProfile,
        analysisProfile: AnalysisProfile
    ) -> String {
        let recentStart = window.start(endingAt: now, calendar: calendar)
        let previousStart = window.previousStart(endingAt: now, calendar: calendar)

        let recent = summaries.filter { $0.startTime >= recentStart }
        let previous = summaries.filter { $0.startTime >= previousStart && $0.startTime < recentStart }
        // The window's own split, before the profile is applied: the week
        // structure judges recovery over everything that happened, whichever
        // half the user asked about (#185).
        let windowStrength = sessions(in: recent, for: .strength)
        let windowEndurance = sessions(in: recent, for: .endurance)
        // A profile that covers nothing this window holds falls back to
        // "Overall load" — see `AnalysisProfile.resolved(for:)`.
        let analysed = analysisProfile.resolved(for: recent)
        let recentStrength = analysed.covers(.strength) ? windowStrength : []
        let recentEndurance = analysed.covers(.endurance) ? windowEndurance : []
        // What the profile left out although the window holds it. Stated, and
        // not silently dropped: the system prompt tells the model that a
        // missing section is training this person did not record, and under a
        // single-domain profile that would be untrue.
        let omitted = AnalysisDomain.allCases.filter { domain in
            guard !analysed.covers(domain) else { return false }
            return !sessions(in: recent, for: domain).isEmpty
        }

        let days = PromptDayFormatter(calendar: calendar)
        var intro = "Here is my own training data. Analyse it and tell me what to do next."
        if !omitted.isEmpty {
            let left = omitted.map(\.displayName).joined(separator: " and ")
            intro += " Analyse my \(analysed.displayName.lowercased()) training only — "
                + "I also recorded \(left) sessions in this window and left them out of "
                + "this analysis on purpose."
        }
        // A widened window means the user did not train for at least the last
        // four weeks. Left unsaid, the model reads the window as a normal one
        // and recommends progression across a break it never noticed (#87).
        if !window.isDefault {
            intro += " I have not trained in the last \(AnalysisWindow.default.weeks) weeks, "
                + "so this covers the last \(window.weeks) weeks instead. Address that break "
                + "explicitly and treat the training before it as what I am returning from."
        }

        // An empty window turns every figure into a zero, which reads as
        // "trained nothing" rather than "nothing recorded" — including the
        // window header itself. Saying it once, plainly, is shorter and truer.
        // Facts about the person come before facts about the data, and only
        // when there are any: `compactMap` drops the section, not its heading.
        let covered = AnalysisDomain.allCases.filter { domain in
            switch domain {
            case .strength: return !recentStrength.isEmpty
            case .endurance: return !recentEndurance.isEmpty
            }
        }
        let opening = [
            intro,
            profileSection(profile, covering: covered.isEmpty ? [.strength] : covered),
        ].compactMap { $0 }

        guard !recent.isEmpty else {
            return (opening + [
                "## Last \(window.weeks) weeks (\(days.string(recentStart)) to \(days.string(now)))",
                "No workouts are recorded in this window. Say so plainly and do not "
                    + "infer a training history from the absence of data.",
            ]).joined(separator: "\n\n")
        }

        var sections = opening
        sections += StrengthPromptSection.sections(
            recent: recentStrength,
            previous: sessions(in: previous, for: .strength),
            exercises: exercises,
            progressions: progressions,
            window: window,
            recentStart: recentStart,
            previousStart: previousStart,
            now: now,
            calendar: calendar,
            days: days
        )
        sections += EndurancePromptSection.sections(
            recent: recentEndurance,
            previous: sessions(in: previous, for: .endurance),
            window: window,
            recentStart: recentStart,
            previousStart: previousStart,
            now: now,
            calendar: calendar,
            days: days
        )
        if let load = LoadPromptSection.section(
            strength: windowStrength,
            endurance: windowEndurance,
            profile: analysed,
            window: window,
            now: now,
            calendar: calendar,
            days: days
        ) {
            sections.append(load)
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Exercises (#173)

    /// The exercises the Exercises section lists, each reduced to the
    /// working set its line states — what a progression card is checked
    /// against (#175).
    ///
    /// Walks the same ranking, the same lookup and the same session choice as
    /// the section itself, so a movement is here exactly when it has a line,
    /// and with exactly the weight that line names.
    static func listedExercises(
        exercises: [ExerciseSummary],
        progressions: [String: ExerciseProgression],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> [ListedExercise] {
        let start = window.start(endingAt: now, calendar: calendar)
        return promptedExercises(from: exercises).compactMap { exercise in
            guard let progression = progressions[exercise.id],
                  let listing = listing(progression, from: start)
            else { return nil }
            return ListedExercise(
                title: exercise.title,
                muscleGroup: exercise.muscleGroup,
                workingSet: listing.last.heaviestWorkingSet,
                smallestStepKg: listing.last.heaviestWorkingSet.flatMap {
                    smallestStep(in: listing.inWindow.sessions, latest: $0)
                }
            )
        }
    }

    /// A movement's sessions inside the window, and the session its line
    /// starts from. `nil` when the window holds none of its sessions.
    ///
    /// Shared with `StrengthPromptSection`, which renders the line: the
    /// section and the validation of #175 have to pick the same session, so
    /// the choice is made in exactly one place.
    static func listing(
        _ progression: ExerciseProgression,
        from start: Date
    ) -> (inWindow: ExerciseProgression, last: ExerciseHistoryEntry)? {
        // Rebuilt over the window alone, so the trend and the plateau verdict
        // describe the same sessions as every other figure in the prompt —
        // whatever range the progression was read over.
        let inWindow = ExerciseProgression(
            id: progression.id,
            title: progression.title,
            sessions: progression.sessions.filter { $0.sessionStart >= start }
        )
        // The most recent session that logged working sets: one holding only
        // warm-ups would report "nothing logged" above a trend drawn from the
        // sessions before it.
        guard let last = inWindow.sessions.last(where: { $0.countedSetCount > 0 })
            ?? inWindow.sessions.last
        else { return nil }
        return (inWindow, last)
    }

    /// The smallest difference between two distinct working weights the user
    /// logged for this exercise in the window — the increment their gym
    /// actually offers, which rule 6 caps a load increase at.
    ///
    /// Only working sets count, the sets the working weight itself is taken
    /// from: a carry's weight next to a press's would be a step between two
    /// different kinds of set. `nil` when fewer than two distinct weights were
    /// logged, and when the step is larger than both `maxStepShare` of
    /// `latest` and `minimumStepKg` — a gap that size is a change of
    /// equipment, not an increment.
    ///
    /// Not private: `listedExercises` hands the same figure to the report
    /// validation (#175), so the step the prompt names and the step a card is
    /// checked against come from this one function.
    static func smallestStep(in sessions: [ExerciseHistoryEntry], latest: WorkingSet) -> Double? {
        // Rounded first, so two floating-point spellings of 62.5 cannot turn
        // into a step of 0.0000001 kg.
        let weights = Set(sessions.flatMap(\.workingSets).map(\.roundedWeightKg)).sorted()
        guard let step = zip(weights, weights.dropFirst()).map({ $1 - $0 }).min(),
              step <= max(latest.weightKg * maxStepShare, minimumStepKg)
        else { return nil }
        return step
    }

    /// Whether rule 6 treats the exercise as a barbell exercise, which it
    /// increases in steps of 2.5 kg whatever step is listed for it.
    ///
    /// Relies on Hevy's exercise titles: every barbell variant in Hevy's
    /// library carries the equipment suffix "(Barbell)", e.g.
    /// "Bench Press (Barbell)". A custom exercise without that suffix is not
    /// a barbell exercise here and falls under the listed-step rule.
    static func isBarbell(title: String) -> Bool {
        title.range(of: "(Barbell)", options: .caseInsensitive) != nil
    }
}
