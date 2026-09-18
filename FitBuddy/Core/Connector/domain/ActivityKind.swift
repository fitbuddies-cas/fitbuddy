import Foundation

/// What kind of training a session was, normalized across providers (#180).
///
/// Before this, the sport lived in the session title as free text — Strava's
/// `TrailRun`, Polar's `TREADMILL_RUNNING` — which forced the prompt builder
/// and the cards to guess, the same failure mode as the muscle-group
/// heuristic. The enum is deliberately coarse: it names the domains the
/// analysis reasons about (strength vs. the endurance disciplines), not every
/// sport a provider can log.
///
/// Each provider maps its own sport vocabulary onto these cases in exactly one
/// place — `StravaActivityDTO.kind(sportType:type:)` and
/// `PolarExerciseDTO.kind(sport:detailed:)`. Anything unrecognised becomes
/// `.other` rather than a wrong guess, so a sport added by a provider
/// tomorrow degrades to "some session" instead of being counted as a run.
enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case strength
    case run
    case ride
    case swim
    case hike
    case walk
    case other

    /// Whether the session is judged with endurance units (km, min/km, bpm)
    /// rather than with kg (US-15 AC5). `.other` is not: an unclassified
    /// session has no unit the analysis may assume.
    var isEndurance: Bool {
        switch self {
        case .run, .ride, .swim, .hike, .walk: return true
        case .strength, .other: return false
        }
    }

    /// Decodes leniently: a raw value written by a newer build reads as
    /// `.other` instead of failing the whole `Activity`. Encoding stays the
    /// synthesized raw-value form.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ActivityKind(rawValue: raw) ?? .other
    }
}
