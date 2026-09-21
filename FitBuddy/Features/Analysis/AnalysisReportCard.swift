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
    /// One figure of the week, with the app's own current value in place of
    /// the model's (US-15 AC5, #186).
    ///
    /// `from` is the weekly aggregate the app computed, `to` and `reasoning`
    /// are the model's, and the delta is derived from the two by
    /// `MetricUnit.delta(from:to:)` — never sent, never stored. `source` is
    /// the header label and is empty where the card has none.
    case metric(label: String, from: Double, to: Double, unit: MetricUnit, reasoning: String, source: String)
    /// Strength and endurance in the same week, with the app's day counts
    /// (US-15 AC2, #186). Only the reasoning is the model's.
    case interference(metrics: InterferenceMetrics, reasoning: String)
    /// A model note, or a card that failed validation, reduced to its text.
    case note(title: String, text: String)

    /// Whether this card states a step that adds training load.
    ///
    /// Since #227 it no longer decides the verdict — `AnalysisVerdictRule`
    /// does, from the app's own figures. What it decides is whether the
    /// **model's lead** may stand under a progress verdict: a lead arguing
    /// for a step no surviving card states is naming a figure the app
    /// rejected, and `AnalysisReportValidator` replaces it with its own
    /// (#170).
    ///
    /// A progression always does. A metric card does when its step is an
    /// improvement in its own unit (`MetricUnit.isImprovement`), so a card
    /// asking for fewer kilometres or an easier heart rate does not hold up a
    /// progress lead, and an endurance report recommending +3 km does.
    var backsProgress: Bool {
        switch self {
        case .progression:
            return true
        case let .metric(_, from, to, unit, _, _):
            return unit.isImprovement(from: from, to: to)
        case .recovery, .imbalance, .interference, .note:
            return false
        }
    }

    var kind: AnalysisCard.Kind {
        switch self {
        case .progression: return .progression
        case .recovery: return .recovery
        case .imbalance: return .imbalance
        case .metric: return .metric
        case .interference: return .interference
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
        case label, from, to, unit, source
        case interference
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
        case .metric:
            self = .metric(
                label: try container.decode(String.self, forKey: .label),
                from: try container.decode(Double.self, forKey: .from),
                to: try container.decode(Double.self, forKey: .to),
                unit: try container.decode(MetricUnit.self, forKey: .unit),
                reasoning: try container.decode(String.self, forKey: .reasoning),
                source: try container.decodeIfPresent(String.self, forKey: .source) ?? ""
            )
        case .interference:
            self = .interference(
                metrics: try container.decode(InterferenceMetrics.self, forKey: .interference),
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
        case let .metric(label, from, to, unit, reasoning, source):
            try container.encode(label, forKey: .label)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(unit, forKey: .unit)
            try container.encode(reasoning, forKey: .reasoning)
            try container.encode(source, forKey: .source)
        case let .interference(metrics, reasoning):
            try container.encode(metrics, forKey: .interference)
            try container.encode(reasoning, forKey: .reasoning)
        case let .note(title, text):
            try container.encode(title, forKey: .title)
            try container.encode(text, forKey: .text)
        }
    }
}
