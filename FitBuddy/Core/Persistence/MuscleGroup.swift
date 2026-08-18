import Foundation

/// Coarse muscle group an exercise loads, derived from its Hevy title.
///
/// Hevy exposes the real classification only through `GET /v1/exercise_templates`,
/// which v0 does not fetch: the dashboard would have to pull, cache and refresh
/// a second endpoint for one chart. The title-based mapping below covers the
/// common movements and puts anything unrecognised into `.other`, so the
/// distribution never claims precision it does not have.
enum MuscleGroup: String, CaseIterable, Sendable, Identifiable {
    case chest
    case back
    case legs
    case shoulders
    case arms
    case core
    /// Cardio, mobility and anything the title mapping does not recognise.
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .legs: return "Legs"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .core: return "Core"
        case .other: return "Other"
        }
    }

    /// Classifies an exercise by its Hevy title, e.g. `Bench Press (Barbell)`.
    ///
    /// The first matching rule wins, so the order below is the specification:
    /// cardio before `row` (Rowing Machine), core before legs (Hanging Leg
    /// Raise), legs before arms (Seated Leg Curl), shoulders before back
    /// (Upright Row).
    static func from(exerciseTitle: String) -> MuscleGroup {
        let title = exerciseTitle.lowercased()
        for (group, keywords) in rules where keywords.contains(where: title.contains) {
            return group
        }
        return .other
    }

    /// Keyword rules in priority order.
    private static let rules: [(MuscleGroup, [String])] = [
        (.other, [
            "treadmill", "running", "jogging", "walking", "cycling", "bike", "elliptical",
            "rowing machine", "stair", "swim", "jump rope", "skipping",
        ]),
        (.core, [
            "crunch", "plank", "sit up", "sit-up", "leg raise", "knee raise", "russian twist",
            "ab wheel", "hollow", "dead bug", "woodchop", "pallof",
        ]),
        (.legs, [
            "squat", "leg press", "leg extension", "leg curl", "lunge", "deadlift", "calf",
            "hip thrust", "glute", "step up", "hack", "adductor", "abductor",
        ]),
        (.shoulders, [
            "shoulder press", "overhead press", "military press", "arnold press", "lateral raise",
            "front raise", "rear delt", "face pull", "upright row", "delt",
        ]),
        (.back, [
            "pull up", "pull-up", "chin up", "chin-up", "pulldown", "pull down", "row",
            "lat ", "pullover", "shrug", "back extension", "good morning",
        ]),
        (.chest, [
            "bench press", "chest", "fly", "flye", "push up", "push-up", "dip", "pec",
        ]),
        (.arms, [
            "curl", "triceps", "tricep", "biceps", "bicep", "pushdown", "skull", "kickback",
            "hammer", "preacher", "wrist", "forearm",
        ]),
    ]
}
