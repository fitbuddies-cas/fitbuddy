import Foundation

/// The effort values of a session as the prompt writes them — each under the
/// label ADR-015 §2 fixes for its scale, never as a bare number (#245, US-18
/// AC1).
///
/// One place for the labels, so the strength session rows, the endurance
/// effort lines and the result screen's "no effort anywhere" check (AC6) all
/// read the same rule for what counts as an effort value and what it is
/// called. The label strings are private on purpose: #246 introduces
/// `EffortScale` with the same ADR-015 labels, and once both are merged these
/// can read `EffortScale.label` instead of keeping a second copy.
///
/// **Nothing here combines two scales** (ADR-015 §1, AC2). A session carrying
/// a Strava Relative Effort and a Polar Cardio Load gets two separately
/// labelled values, never a sum, a mean or a ratio of them. The only mean is
/// Hevy's RPE over the sets of one session, which stays within its own scale.
///
/// **A missing value is left out**, never written as `0`, "—" or a
/// placeholder (ADR-015 §2). Polar's legacy `training_load` has no label and
/// is never read here (ADR-015 §2).
enum EffortPromptFigures {
    /// Hevy's RPE. Unprefixed — ADR-015 reserves the bare "RPE" for Hevy —
    /// and spelled "mean RPE" like the Exercises section, because the figure
    /// is the mean over a session's sets.
    private static let hevyRPELabel = "mean RPE"
    private static let stravaRelativeEffortLabel = "Strava Relative Effort"
    private static let polarCardioLoadLabel = "Polar Cardio Load"
    private static let polarMuscleLoadLabel = "Polar Muscle Load"
    private static let polarPerceivedLoadLabel = "Polar Perceived Load"
    private static let polarRPELabel = "Polar RPE"

    /// The session's effort values in a fixed order — Hevy's RPE, Strava's
    /// Relative Effort, then Polar's Training Load Pro values. Empty when the
    /// session carries none. Each value is the scale's label and the value as
    /// the prompt writes it.
    static func values(of summary: WorkoutSummary) -> [(label: String, text: String)] {
        var values: [(label: String, text: String)] = []
        if let rpe = summary.averageRPE, rpe.isFinite {
            values.append((hevyRPELabel, PlainWeightFormatter.string(rpe, decimals: 1)))
        }
        guard let cardio = summary.cardio else { return values }
        let scores: [(label: String, value: Double?)] = [
            (stravaRelativeEffortLabel, cardio.relativeEffort),
            (polarCardioLoadLabel, cardio.cardioLoad),
            (polarMuscleLoadLabel, cardio.muscleLoad),
            (polarPerceivedLoadLabel, cardio.perceivedLoad),
        ]
        for score in scores {
            if let text = score.value.flatMap(Self.score) {
                values.append((score.label, text))
            }
        }
        if let level = cardio.userRPE.flatMap(polarRPELevel) {
            values.append((polarRPELabel, "\"\(level)\""))
        }
        return values
    }

    /// The session's effort values as they stand in a session row:
    /// `["mean RPE 7.5", "Strava Relative Effort 45"]`.
    static func labelledValues(of summary: WorkoutSummary) -> [String] {
        values(of: summary).map { "\($0.label) \($0.text)" }
    }

    /// The sessions' values grouped by scale, one group per label in the
    /// fixed order above, each group's entries in the order of `sessions`.
    /// Scales no session recorded are left out. Grouping is all it does:
    /// nothing inside a group is summed or averaged either.
    static func byScale(
        _ sessions: [WorkoutSummary]
    ) -> [(label: String, entries: [(session: WorkoutSummary, text: String)])] {
        let order = [
            hevyRPELabel, stravaRelativeEffortLabel, polarCardioLoadLabel,
            polarMuscleLoadLabel, polarPerceivedLoadLabel, polarRPELabel,
        ]
        var groups: [String: [(session: WorkoutSummary, text: String)]] = [:]
        for session in sessions {
            for value in values(of: session) {
                groups[value.label, default: []].append((session, value.text))
            }
        }
        return order.compactMap { label in
            groups[label].map { (label, $0) }
        }
    }

    /// Whether the session carries at least one effort value the prompt
    /// would show.
    static func hasEffort(_ summary: WorkoutSummary) -> Bool {
        !values(of: summary).isEmpty
    }

    /// Whether any of the sessions carries an effort value — from any source
    /// (#245, US-18 AC6).
    static func containsEffort(_ summaries: [WorkoutSummary]) -> Bool {
        summaries.contains(where: hasEffort)
    }

    /// Polar's RPE level as the prompt names it — a level name, never a
    /// number (ADR-015 §5) — or `nil` where the level says nothing.
    ///
    /// `.none` and `.unknown` count as missing (product-owner decision on
    /// #245): "none" is not a rating of the session, and `.unknown` is a label
    /// this build could not read. Every case name besides `RPE_NONE`,
    /// `RPE_BRISK` and `RPE_EXTREME` follows #244's vocabulary and is
    /// **unverified** against a real AccessLink response; this is the one
    /// place to correct the wording if Polar spells a level differently.
    static func polarRPELevel(_ rpe: PolarUserRPE) -> String? {
        switch rpe {
        case .none, .unknown: return nil
        case .veryEasy: return "very easy"
        case .easy: return "easy"
        case .moderate: return "moderate"
        case .brisk: return "brisk"
        case .hard: return "hard"
        case .veryHard: return "very hard"
        case .exhausting: return "exhausting"
        case .maximal: return "maximal"
        case .extreme: return "extreme"
        }
    }

    /// A provider score as data, or `nil` when it is no measurement.
    ///
    /// A zero is treated as unrecorded, like a zero heart rate elsewhere in the
    /// prompt: a provider that writes `0` for a session without a strap or a
    /// power meter is saying "not measured", and a `0` in the prompt would read
    /// as the easiest session on record.
    private static func score(_ value: Double) -> String? {
        guard value.isFinite, value > 0 else { return nil }
        return PlainWeightFormatter.string(value, decimals: 1)
    }
}
