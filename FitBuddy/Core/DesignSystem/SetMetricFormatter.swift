import Foundation

/// Formats the metrics of a single logged set for the detail screen (#98).
///
/// Every function returns an optional and hands `nil` straight back: Hevy logs
/// only what the exercise type requires, and the screen renders exactly what
/// was logged. Turning a missing weight into `"0 kg"` would claim the user
/// lifted nothing, which is a different statement from not having logged one.
enum SetMetricFormatter {
    /// `62.5` → `"62.5 kg"`, `60` → `"60 kg"`.
    ///
    /// Half-kilo plates are the smallest step on the bar, so one decimal is
    /// enough — and a trailing `.0` on a round weight is noise.
    static func weight(_ kilograms: Double?) -> String? {
        guard let kilograms else { return nil }
        return kilograms.formatted(.number.precision(.fractionLength(0...1))) + " kg"
    }

    /// `8` → `"8 reps"`, `1` → `"1 rep"`.
    static func reps(_ reps: Int?) -> String? {
        guard let reps else { return nil }
        return CountFormatter.labelled(reps, singular: "rep")
    }

    /// `800` → `"800 m"`, `5000` → `"5.0 km"`.
    ///
    /// The unit rules are `DistanceFormatter`'s since #181, so a distance
    /// logged as a set and the same distance on an endurance card read the
    /// same. What stays here is the optional: a set without a logged distance
    /// shows no distance, which is a different statement from `"0 m"`.
    static func distance(_ meters: Double?) -> String? {
        guard let meters else { return nil }
        return DistanceFormatter.display(meters)
    }

    /// `90` → `"1:30"`, `45` → `"0:45"`, `3_725` → `"1:02:05"`.
    ///
    /// The clock form rather than `"1 min 30 s"`: a set duration is read like
    /// a stopwatch, and the rows line up under tabular numerals.
    static func duration(_ seconds: Int?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        let minutes = (seconds / 60) % 60
        let remainder = seconds % 60
        guard seconds >= 3_600 else {
            return String(format: "%d:%02d", minutes, remainder)
        }
        return String(format: "%d:%02d:%02d", seconds / 3_600, minutes, remainder)
    }

    /// `9.5` → `"RPE 9.5"`, `8` → `"RPE 8"`.
    static func rpe(_ rpe: Double?) -> String? {
        guard let rpe else { return nil }
        return "RPE " + rpe.formatted(.number.precision(.fractionLength(0...1)))
    }
}
