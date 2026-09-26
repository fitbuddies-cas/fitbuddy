import Foundation

/// The unit an `AnalysisInterventionFigure` is stated in (#228).
enum AnalysisFigureUnit: String, Codable, CaseIterable, Equatable, Sendable {
    case kilograms
    case repetitions
    /// Sessions per week of a muscle group — the imbalance card's figure.
    case sessionsPerWeek
    case kilometers
    case minutesPerKilometer
    case beatsPerMinute
    case hours

    /// The unit of a metric card's figure.
    init(_ unit: MetricUnit) {
        switch unit {
        case .kilograms: self = .kilograms
        case .kilometers: self = .kilometers
        case .minutesPerKilometer: self = .minutesPerKilometer
        case .beatsPerMinute: self = .beatsPerMinute
        case .hours: self = .hours
        }
    }

    /// Short suffix for the debug view.
    var symbol: String {
        switch self {
        case .kilograms: return "kg"
        case .repetitions: return "reps"
        case .sessionsPerWeek: return "/wk"
        case .kilometers: return "km"
        case .minutesPerKilometer: return "min/km"
        case .beatsPerMinute: return "bpm"
        case .hours: return "h"
        }
    }
}
