import Foundation

/// How long the user has been strength training (US-13 AC1).
///
/// Deliberately *strength* training, and deliberately in years. Five years of
/// running and six months of lifting are two different numbers for a
/// recommendation, and the analysis reads strength sessions only — so the
/// narrower question is the honest one while that holds. Years rather than
/// beginner/intermediate/advanced because a self-assessment is not comparable
/// between two people, or between the same person a year apart.
///
/// The raw values are persisted — see `TrainingGoal`.
enum TrainingExperience: String, CaseIterable, Sendable {
    case underOneYear = "under_1y"
    case oneToThreeYears = "1_to_3y"
    case overThreeYears = "over_3y"

    var displayName: String {
        switch self {
        case .underOneYear: return "Less than a year"
        case .oneToThreeYears: return "1–3 years"
        case .overThreeYears: return "More than 3 years"
        }
    }
}
