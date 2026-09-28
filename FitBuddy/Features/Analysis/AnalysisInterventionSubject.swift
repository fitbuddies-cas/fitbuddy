import Foundation

/// What part of the model's answer the validator intervened in (#228): one of
/// its cards, by kind, or one of the report-level fields the app can replace.
///
/// One flat enum rather than a card kind plus a separate "part", so a log
/// entry reads as one word and the tally in the debug view can key on it.
enum AnalysisInterventionSubject: String, Codable, CaseIterable, Equatable, Sendable {
    case progression
    case repProgression
    case recovery
    case imbalance
    case metric
    case interference
    case note
    /// The verdict the model chose (ADR-014 §7).
    case verdict
    case headline
    case lead

    /// The subject of a card of `kind`.
    init(_ kind: AnalysisCard.Kind) {
        switch kind {
        case .progression: self = .progression
        case .repProgression: self = .repProgression
        case .recovery: self = .recovery
        case .imbalance: self = .imbalance
        case .metric: self = .metric
        case .interference: self = .interference
        case .note: self = .note
        }
    }
}
