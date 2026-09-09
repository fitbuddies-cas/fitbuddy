import Foundation

/// The fitness-data providers FitBuddy knows about (ADR-6). Identifies a
/// connector inside `ConnectorRegistry` without the registry ever touching a
/// provider-specific type — the registry stores `any FitnessConnector`, keyed
/// by this.
///
/// `strava` is listed although only `StravaConnector`'s stub exists in v0: the
/// case is what lets the registry, and the renewal prompt from US-5 AC2, be
/// written and tested before the OAuth flow lands in v1.
enum ConnectorSource: String, CaseIterable, Identifiable, Sendable {
    case hevy
    case strava

    var id: String { rawValue }

    /// User-facing provider name.
    var displayName: String {
        switch self {
        case .hevy: return "Hevy"
        case .strava: return "Strava"
        }
    }

    /// Prompt shown when this source's stored credentials have expired
    /// (US-5 AC2) — the label of the link back into the provider's re-auth
    /// flow.
    var renewalPrompt: String {
        "Renew your \(displayName) connection"
    }
}
