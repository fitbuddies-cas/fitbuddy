import Foundation

/// One effort scale the verdict rule reads (US-18 AC4, #246).
///
/// **The unit is the scale, not the provider** (ADR-015 §1): Polar
/// contributes three scales and none of them is merged with another. No two
/// cases are ever summed, averaged or compared with each other — each is a
/// trend against itself only (ADR-014 §3).
///
/// Deliberately absent:
/// - Polar's `user-rpe` (`CardioMetrics.userRPE`) — an ordered enum without
///   numbers, so there is no mean to trend (ADR-015 §5).
/// - Polar's legacy `training_load` (`CardioMetrics.trainingLoad`) — no label
///   and not read in v0 (ADR-015 §2).
enum EffortScale: String, CaseIterable, Codable, Sendable {
    /// Hevy's RPE, one value per session: the mean over that session's
    /// counted sets that logged one (`WorkoutSummary.averageRPE`).
    case hevyRPE
    /// Strava's Relative Effort (`CardioMetrics.relativeEffort`).
    case stravaRelativeEffort
    /// Polar's Cardio Load (`CardioMetrics.cardioLoad`).
    case polarCardioLoad
    /// Polar's Perceived Load (`CardioMetrics.perceivedLoad`).
    case polarPerceivedLoad
    /// Polar's Muscle Load (`CardioMetrics.muscleLoad`).
    case polarMuscleLoad

    /// The source label of ADR-015 §2 — never a bare number without it.
    var label: String {
        switch self {
        case .hevyRPE: return "RPE"
        case .stravaRelativeEffort: return "Strava Relative Effort"
        case .polarCardioLoad: return "Polar Cardio Load"
        case .polarPerceivedLoad: return "Polar Perceived Load"
        case .polarMuscleLoad: return "Polar Muscle Load"
        }
    }

    /// The provider whose sessions carry this scale.
    var source: ConnectorSource {
        switch self {
        case .hevyRPE: return .hevy
        case .stravaRelativeEffort: return .strava
        case .polarCardioLoad, .polarPerceivedLoad, .polarMuscleLoad: return .polar
        }
    }

    /// The domain the scale speaks about (ADR-014 §5): Hevy's RPE is a
    /// statement about strength work, the Strava and Polar scales about
    /// endurance work.
    var domain: AnalysisDomain {
        switch self {
        case .hevyRPE: return .strength
        case .stravaRelativeEffort, .polarCardioLoad, .polarPerceivedLoad, .polarMuscleLoad:
            return .endurance
        }
    }

    /// Whether stage 5 reads this scale under `profile` (ADR-014 §5):
    /// "Strength" reads Hevy's RPE only, "Endurance" the Strava and Polar
    /// scales, "Overall load" every scale — each on its own.
    func isRead(under profile: AnalysisProfile) -> Bool {
        profile.covers(domain)
    }

    /// The value `session` recorded on this scale, or `nil` when it recorded
    /// none — never a stand-in (ADR-014 §4).
    ///
    /// A session from another provider has no value here, whatever its
    /// fields hold: the scale is the provider's own. A value of zero or below
    /// is read as "not measured", as `RecoveryMetrics.meanHeartRate(in:)`
    /// reads a zero heart rate — no scale here has a meaningful zero session,
    /// and a zero would otherwise pull a mean down with a measurement nobody
    /// made.
    func value(of session: WorkoutSummary) -> Double? {
        guard session.source == source else { return nil }
        let value: Double?
        switch self {
        case .hevyRPE: value = session.averageRPE
        case .stravaRelativeEffort: value = session.cardio?.relativeEffort
        case .polarCardioLoad: value = session.cardio?.cardioLoad
        case .polarPerceivedLoad: value = session.cardio?.perceivedLoad
        case .polarMuscleLoad: value = session.cardio?.muscleLoad
        }
        guard let value, value > 0 else { return nil }
        return value
    }
}
