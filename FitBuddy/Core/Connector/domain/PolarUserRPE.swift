import Foundation

/// The rating of perceived exertion a Polar user gave a session, as Polar
/// AccessLink reports it in `training_load_pro.user-rpe` (#244) — the only
/// subjective effort value Polar has.
///
/// Kept as Polar's own ordered labels, deliberately **without** a numeric
/// value: Polar documents no mapping onto a 1–10 scale, and assigning one
/// here (`brisk = 5`) would be a guess that later reads like a measurement.
/// If a number is ever needed, that is a documented decision in ADR-015
/// (#242), not a silent one here. The cases are declared in Polar's order,
/// from `none` to `extreme`.
///
/// AccessLink's public reference only shows `UNKNOWN` for this field; the
/// ten labels follow the Polar vocabulary named in #244. Any string this
/// build does not know — `UNKNOWN`, a label Polar adds later, or a label
/// spelled differently — reads as `.unknown` instead of failing the whole
/// session.
enum PolarUserRPE: String, Codable, CaseIterable, Hashable, Sendable {
    case none = "RPE_NONE"
    case veryEasy = "RPE_VERY_EASY"
    case easy = "RPE_EASY"
    case moderate = "RPE_MODERATE"
    case brisk = "RPE_BRISK"
    case hard = "RPE_HARD"
    case veryHard = "RPE_VERY_HARD"
    case exhausting = "RPE_EXHAUSTING"
    case maximal = "RPE_MAXIMAL"
    case extreme = "RPE_EXTREME"
    /// A value this build cannot name — never a rating in its own right.
    case unknown = "UNKNOWN"

    /// Polar's raw label, or `.unknown` for any label this build does not
    /// know.
    init(polarValue: String) {
        self = PolarUserRPE(rawValue: polarValue) ?? .unknown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(polarValue: try container.decode(String.self))
    }
}
