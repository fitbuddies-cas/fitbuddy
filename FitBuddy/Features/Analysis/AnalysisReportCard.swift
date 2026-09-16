import Foundation

/// A card of a `ValidatedAnalysisReport`: checked against the cache, with the
/// app's own figures in place of the model's (US-14 AC2–AC4, #175).
///
/// The counterpart to `AnalysisCard`, which is the model's answer as sent.
/// Everything a card here states as a measurement comes from the app: the
/// exercise title, muscle group and starting weight of a progression, the
/// per-week figures of an imbalance, every metric of a recovery card. Only the
/// target weight and the reasoning are the model's. The imbalance bar lengths
/// stay with the view, which derives them from the two per-week figures.
///
/// Encoded like `AnalysisCard`: a flat object with `kind` as discriminator.
enum AnalysisReportCard: Equatable, Sendable {
    case progression(exercise: String, muscleGroup: MuscleGroup, fromKg: Double, toKg: Double, reasoning: String)
    case recovery(reasoning: String, metrics: RecoveryMetrics)
    case imbalance(groupA: MuscleGroup, perWeekA: Double, groupB: MuscleGroup, perWeekB: Double, reasoning: String)
    /// A model note, or a card that failed validation, reduced to its text.
    case note(title: String, text: String)

    var kind: AnalysisCard.Kind {
        switch self {
        case .progression: return .progression
        case .recovery: return .recovery
        case .imbalance: return .imbalance
        case .note: return .note
        }
    }
}

extension AnalysisReportCard: Codable {
    enum CodingKeys: String, CodingKey {
        case kind
        case exercise, muscleGroup, fromKg, toKg
        case metrics
        case groupA, perWeekA, groupB, perWeekB
        case reasoning
        case title, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(AnalysisCard.Kind.self, forKey: .kind) {
        case .progression:
            self = .progression(
                exercise: try container.decode(String.self, forKey: .exercise),
                muscleGroup: try container.decode(MuscleGroup.self, forKey: .muscleGroup),
                fromKg: try container.decode(Double.self, forKey: .fromKg),
                toKg: try container.decode(Double.self, forKey: .toKg),
                reasoning: try container.decode(String.self, forKey: .reasoning)
            )
        case .recovery:
            self = .recovery(
                reasoning: try container.decode(String.self, forKey: .reasoning),
                metrics: try container.decode(RecoveryMetrics.self, forKey: .metrics)
            )
        case .imbalance:
            self = .imbalance(
                groupA: try container.decode(MuscleGroup.self, forKey: .groupA),
                perWeekA: try container.decode(Double.self, forKey: .perWeekA),
                groupB: try container.decode(MuscleGroup.self, forKey: .groupB),
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
        case let .recovery(reasoning, metrics):
            try container.encode(reasoning, forKey: .reasoning)
            try container.encode(metrics, forKey: .metrics)
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
