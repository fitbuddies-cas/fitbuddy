import Foundation

/// What the user is training towards (US-13 AC1).
///
/// Five options, and the fifth is the one that is easy to forget: Strava and
/// Polar are connected in Settings, not during onboarding, so the step asking
/// this question does not know whether a lifter or a runner is in front of it.
/// Without `improveEndurance` a runner picks "stay fit" and gets a strength
/// block recommended.
///
/// The raw values are persisted, so they are spelled out rather than derived
/// from the case names — renaming a case must not change what is on disk.
enum TrainingGoal: String, CaseIterable, Sendable {
    case buildMuscle = "build_muscle"
    case getStronger = "get_stronger"
    case loseFat = "lose_fat"
    case improveEndurance = "improve_endurance"
    case stayFit = "stay_fit"

    /// The label on the option, and the wording the prompt uses (#192) — one
    /// phrasing, so what the user picked is what the model reads.
    var displayName: String {
        switch self {
        case .buildMuscle: return "Build muscle"
        case .getStronger: return "Get stronger"
        case .loseFat: return "Lose fat"
        case .improveEndurance: return "Improve endurance"
        case .stayFit: return "Stay fit"
        }
    }
}
