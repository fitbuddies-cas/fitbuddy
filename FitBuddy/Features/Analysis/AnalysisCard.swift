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
    /// Rest before any progression.
    case recovery(reasoning: String, suggestedRestHours: Double)
    /// Two muscle groups trained at clearly different frequencies.
    case imbalance(groupA: String, perWeekA: Double, groupB: String, perWeekB: Double, reasoning: String)
    /// Anything else worth saying, e.g. a rep progression without a weight
    /// change.
    case note(title: String, text: String)

    /// The `kind` discriminator of each case, as it appears on the wire and in
    /// the schema.
    enum Kind: String, Codable, CaseIterable, Sendable {
        case progression
        case recovery
        case imbalance
        case note
    }

    /// The card's explanatory sentence — what a prose rendering of the card
    /// says when there is no room for its figures.
    var prose: String {
        switch self {
        case .progression(_, _, _, _, let reasoning),
             .recovery(let reasoning, _),
             .imbalance(_, _, _, _, let reasoning):
            return reasoning
        case .note(_, let text):
            return text
        }
    }

    var kind: Kind {
        switch self {
        case .progression: return .progression
        case .recovery: return .recovery
        case .imbalance: return .imbalance
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
        case suggestedRestHours
        case groupA, perWeekA, groupB, perWeekB
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
        case let .recovery(reasoning, suggestedRestHours):
            try container.encode(reasoning, forKey: .reasoning)
            try container.encode(suggestedRestHours, forKey: .suggestedRestHours)
        case let .imbalance(groupA, perWeekA, groupB, perWeekB, reasoning):
            try container.encode(groupA, forKey: .groupA)
            try container.encode(perWeekA, forKey: .perWeekA)
            try container.encode(groupB, forKey: .groupB)
            try container.encode(perWeekB, forKey: .perWeekB)
            try container.encode(reasoning, forKey: .reasoning)
        case let .note(title, text):
            try container.encode(title, forKey: .title)
            try container.encode(text, forKey: .text)
        }
    }
}
