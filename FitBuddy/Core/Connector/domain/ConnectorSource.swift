import Foundation

/// The fitness-data providers FitBuddy knows about (ADR-6). Identifies a
/// connector inside `ConnectorRegistry` without the registry ever touching a
/// provider-specific type — the registry stores `any FitnessConnector`, keyed
/// by this.
///
/// `strava` was listed before its connector existed, so the registry and the
/// renewal prompt from US-5 AC2 could be written against it; since #142 the
/// real `StravaConnector` stands behind it.
///
/// `polar` is the third source (`PolarConnector`, ADR-11), connected from
/// Settings the same way as Strava.
///
/// `Codable` because `Activity` carries it (#141) and `Activity` is the
/// connector-facing wire boundary.
enum ConnectorSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case hevy
    case strava
    case polar

    var id: String { rawValue }

    /// User-facing provider name.
    var displayName: String {
        switch self {
        case .hevy: return "Hevy"
        case .strava: return "Strava"
        case .polar: return "Polar"
        }
    }

    /// Prompt shown when this source's stored credentials have expired
    /// (US-5 AC2) — the label of the link back into the provider's re-auth
    /// flow.
    var renewalPrompt: String {
        "Renew your \(displayName) connection"
    }
}
