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
    /// Two rules decide, and both matter for what the chart ends up claiming:
    ///
    /// - Keywords match on **word boundaries**, so `Rowing Machine` is cardio
    ///   rather than a rowing movement for the back.
    /// - The **longest** matching keyword wins, so a specific movement beats a
    ///   generic one no matter how the table below is ordered: `Walking Lunge`
    ///   is legs and not cardio, `Hamstring Curl` is legs and not arms,
    ///   `Reverse Fly` is shoulders and not chest.
    ///
    /// Getting this wrong would not empty the chart, it would quietly move
    /// volume from one bar to another — a wrong answer instead of a missing one.
    static func from(exerciseTitle: String) -> MuscleGroup {
        let title = normalized(exerciseTitle)
        var best: (group: MuscleGroup, length: Int)?

        for (group, keywords) in rules {
            for keyword in keywords where matches(keyword, in: title) {
                if keyword.count > (best?.length ?? 0) {
                    best = (group, keyword.count)
                }
            }
        }
        return best?.group ?? .other
    }

    /// Lowercased, stripped of punctuation and padded with spaces, so keywords
    /// can be matched on word boundaries: `Push-Up (Weighted)` → ` push up
    /// weighted `.
    private static func normalized(_ title: String) -> String {
        let words = title.lowercased().split { !$0.isLetter && !$0.isNumber }
        return " " + words.joined(separator: " ") + " "
    }

    /// Whether `keyword` appears as whole words, in singular or plural — Hevy's
    /// own titles are singular, user-created ones are not always ("Dips").
    private static func matches(_ keyword: String, in title: String) -> Bool {
        [" \(keyword) ", " \(keyword)s ", " \(keyword)es "].contains { title.contains($0) }
    }

    /// Keyword table. Order only breaks ties between keywords of equal length.
    private static let rules: [(MuscleGroup, [String])] = [
        (.other, [
            "treadmill", "running", "jogging", "walking", "cycling", "bike", "elliptical",
            "rowing machine", "stair", "swim", "jump rope", "skipping",
        ]),
        (.core, [
            "crunch", "plank", "sit up", "leg raise", "knee raise", "russian twist",
            "ab wheel", "hollow", "dead bug", "woodchop", "pallof",
        ]),
        (.legs, [
            "squat", "leg press", "leg extension", "leg curl", "hamstring", "lunge",
            "walking lunge", "deadlift", "calf", "hip thrust", "glute", "step up",
            "hack", "adductor", "abductor",
        ]),
        (.shoulders, [
            "shoulder press", "overhead press", "military press", "arnold press",
            "lateral raise", "front raise", "rear delt", "reverse fly", "face pull",
            "upright row", "delt",
        ]),
        (.back, [
            "pull up", "chin up", "pulldown", "pull down", "row", "chest supported row",
            "lat", "pullover", "shrug", "back extension", "good morning",
        ]),
        (.chest, [
            "bench press", "chest", "fly", "flye", "push up", "dip", "pec",
        ]),
        (.arms, [
            "curl", "triceps", "tricep", "biceps", "bicep", "pushdown", "skull crusher",
            "kickback", "hammer", "preacher", "wrist", "forearm",
        ]),
    ]
}
