import Foundation

/// One recommendation card of an `AnalysisReport` (US-14 AC2–AC4, #174).
///
/// On the wire each card is a flat object whose `kind` names the case and
/// whose other keys are the case's labels:
///
///     {"kind": "progression", "exercise": "Bench Press", "muscleGroup": "Chest",
///      "fromKg": 60, "toKg": 62.5, "reasoning": "…"}
///
/// Numbers stay numbers: the screen formats weights and the delta itself.
/// Figures the app computes — sessions in the last 7 days and mean RPE on the
/// recovery card, the bar lengths of the imbalance card — are deliberately not
/// part of the model's answer.
enum AnalysisCard: Equatable, Sendable {
    /// A load increase on one exercise. `fromKg` is meant to be the weight of
    /// its most recent session; #175 checks that against the cache.
    case progression(exercise: String, muscleGroup: String, fromKg: Double, toKg: Double, reasoning: String)
    /// More repetitions at the listed weight on one exercise (US-17 AC3,
    /// #234) — the lever where a load increase is not on: the 2-for-2 rule
    /// not met or not checkable, or no load step for the equipment (ADR-013).
    /// `weightKg` and `fromReps` are meant to be the working set the prompt
    /// listed; #233 checks both against the cache.
    case repProgression(exercise: String, muscleGroup: String, weightKg: Double, fromReps: Int, toReps: Int, reasoning: String)
    /// Rest before any progression.
    case recovery(reasoning: String, suggestedRestHours: Double)
    /// Two muscle groups trained at clearly different frequencies.
    case imbalance(groupA: String, perWeekA: Double, groupB: String, perWeekB: Double, reasoning: String)
    /// One figure of the training week, from where it stands to where the
    /// model recommends it goes, in whatever unit that figure is measured in
    /// (US-15 AC5, #186).
    ///
    /// The generic card. `source` is the small label on the right of the
    /// header — "Run", "Strength", "Chest" — and may be empty, in which case
    /// no label is drawn. `from` is meant to be the app's own weekly figure;
    /// #175 checks it against the aggregate and replaces it with the app's.
    /// The difference is **not** on the wire: the app computes it, because a
    /// delta the model wrote could disagree with the two figures printed
    /// beside it.
    ///
    /// **`.progression` is deliberately not folded into this case**, although
    /// `.metric(unit: .kilograms)` can state the same numbers. A progression
    /// carries an exercise and a muscle group this case has no slot for; it is
    /// validated against the listed exercises and the barbell step of prompt
    /// rule 6, which is nothing like a check against a weekly aggregate; and
    /// US-14's schema, prompt and card view all name it. Merging the two would
    /// either lose the exercise or force every metric card to carry two fields
    /// only kilograms ever fills. The prompt therefore asks for `progression`
    /// for a load increase on one exercise and for `metric` for a figure of
    /// the week as a whole.
    case metric(label: String, from: Double, to: Double, unit: MetricUnit, reasoning: String, source: String)
    /// Strength and endurance in the same week: how many days carried each,
    /// and how many carried both (US-15 AC2, #186).
    ///
    /// The three counts are the model's reading back of what the prompt's week
    /// structure told it. The app ignores them and uses its own, like the
    /// recovery card's figures — they are on the wire only so the model has to
    /// commit to the week it is reasoning about.
    case interference(strengthDays: Int, cardioDays: Int, overlapDays: Int, reasoning: String)
    /// Anything else worth saying.
    case note(title: String, text: String)

    /// The `kind` discriminator of each case, as it appears on the wire and in
    /// the schema.
    enum Kind: String, Codable, CaseIterable, Sendable {
        case progression
        case repProgression
        case recovery
        case imbalance
        case metric
        case interference
        case note
    }

    /// The card's explanatory sentence — what a prose rendering of the card
    /// says when there is no room for its figures.
    var prose: String {
        switch self {
        case .progression(_, _, _, _, let reasoning),
             .repProgression(_, _, _, _, _, let reasoning),
             .recovery(let reasoning, _),
             .imbalance(_, _, _, _, let reasoning),
             .metric(_, _, _, _, let reasoning, _),
             .interference(_, _, _, let reasoning):
            return reasoning
        case .note(_, let text):
            return text
        }
    }

    var kind: Kind {
        switch self {
        case .progression: return .progression
        case .repProgression: return .repProgression
        case .recovery: return .recovery
        case .imbalance: return .imbalance
        case .metric: return .metric
        case .interference: return .interference
        case .note: return .note
        }
    }
}

extension AnalysisCard: Codable {
    /// Every key any case uses. `AnalysisReportSchema` names the same keys per
    /// kind; a test keeps the two in step.
    enum CodingKeys: String, CodingKey {
        case kind
        case exercise, muscleGroup, fromKg, toKg
        case weightKg, fromReps, toReps
        case suggestedRestHours
        case groupA, perWeekA, groupB, perWeekB
        case label, from, to, unit, source
        case strengthDays, cardioDays, overlapDays
        case reasoning
        case title, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .progression:
            self = .progression(
                exercise: try container.decode(String.self, forKey: .exercise),
                muscleGroup: try container.decode(String.self, forKey: .muscleGroup),
                fromKg: try container.decode(Double.self, forKey: .fromKg),
                toKg: try container.decode(Double.self, forKey: .toKg),
                reasoning: try container.decode(String.self, forKey: .reasoning)
            )
        case .repProgression:
            self = .repProgression(
                exercise: try container.decode(String.self, forKey: .exercise),
                muscleGroup: try container.decode(String.self, forKey: .muscleGroup),
                weightKg: try container.decode(Double.self, forKey: .weightKg),
                fromReps: try container.decode(Int.self, forKey: .fromReps),
                toReps: try container.decode(Int.self, forKey: .toReps),
                reasoning: try container.decode(String.self, forKey: .reasoning)
            )
        case .recovery:
            self = .recovery(
                reasoning: try container.decode(String.self, forKey: .reasoning),
                suggestedRestHours: try container.decode(Double.self, forKey: .suggestedRestHours)
            )
        case .imbalance:
            self = .imbalance(
                groupA: try container.decode(String.self, forKey: .groupA),
                perWeekA: try container.decode(Double.self, forKey: .perWeekA),
                groupB: try container.decode(String.self, forKey: .groupB),
                perWeekB: try container.decode(Double.self, forKey: .perWeekB),
                reasoning: try container.decode(String.self, forKey: .reasoning)
            )
        case .metric:
            self = .metric(
                label: try container.decode(String.self, forKey: .label),
                from: try container.decode(Double.self, forKey: .from),
                to: try container.decode(Double.self, forKey: .to),
                unit: try container.decode(MetricUnit.self, forKey: .unit),
                reasoning: try container.decode(String.self, forKey: .reasoning),
                // The only optional key across every card: the schema asks for
                // it, but an empty header label is a card without a source,
                // not a broken card.
                source: try container.decodeIfPresent(String.self, forKey: .source) ?? ""
            )
        case .interference:
            self = .interference(
                strengthDays: try container.decode(Int.self, forKey: .strengthDays),
                cardioDays: try container.decode(Int.self, forKey: .cardioDays),
                overlapDays: try container.decode(Int.self, forKey: .overlapDays),
                reasoning: try container.decode(String.self, forKey: .reasoning)
            )
        case .note:
            self = .note(
                title: try container.decode(String.self, forKey: .title),
                text: try container.decode(String.self, forKey: .text)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case let .progression(exercise, muscleGroup, fromKg, toKg, reasoning):
            try container.encode(exercise, forKey: .exercise)
            try container.encode(muscleGroup, forKey: .muscleGroup)
            try container.encode(fromKg, forKey: .fromKg)
            try container.encode(toKg, forKey: .toKg)
            try container.encode(reasoning, forKey: .reasoning)
        case let .repProgression(exercise, muscleGroup, weightKg, fromReps, toReps, reasoning):
            try container.encode(exercise, forKey: .exercise)
            try container.encode(muscleGroup, forKey: .muscleGroup)
            try container.encode(weightKg, forKey: .weightKg)
            try container.encode(fromReps, forKey: .fromReps)
            try container.encode(toReps, forKey: .toReps)
            try container.encode(reasoning, forKey: .reasoning)
        case let .recovery(reasoning, suggestedRestHours):
            try container.encode(reasoning, forKey: .reasoning)
            try container.encode(suggestedRestHours, forKey: .suggestedRestHours)
        case let .imbalance(groupA, perWeekA, groupB, perWeekB, reasoning):
            try container.encode(groupA, forKey: .groupA)
            try container.encode(perWeekA, forKey: .perWeekA)
            try container.encode(groupB, forKey: .groupB)
            try container.encode(perWeekB, forKey: .perWeekB)
            try container.encode(reasoning, forKey: .reasoning)
        case let .metric(label, from, to, unit, reasoning, source):
            try container.encode(label, forKey: .label)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(unit, forKey: .unit)
            try container.encode(reasoning, forKey: .reasoning)
            try container.encode(source, forKey: .source)
        case let .interference(strengthDays, cardioDays, overlapDays, reasoning):
            try container.encode(strengthDays, forKey: .strengthDays)
            try container.encode(cardioDays, forKey: .cardioDays)
            try container.encode(overlapDays, forKey: .overlapDays)
            try container.encode(reasoning, forKey: .reasoning)
        case let .note(title, text):
            try container.encode(title, forKey: .title)
            try container.encode(text, forKey: .text)
        }
    }
}
