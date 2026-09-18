import Foundation

/// Formats a covered distance wherever the app shows one — endurance sessions
/// on the detail screen, the endurance cards of the cross-source analysis
/// (US-15, #181).
///
/// Its own formatter rather than `SetMetricFormatter.distance`: that one
/// formats the metrics of a single logged set and hands `nil` straight back,
/// while a session or a weekly aggregate always has a distance. The unit rules
/// live here once, and `SetMetricFormatter` defers to them.
enum DistanceFormatter {
    /// `850` → `"850 m"`, `8_400` → `"8.4 km"`, `104_300` → `"104 km"`,
    /// `32_000` → `"32 km"`.
    ///
    /// Three ranges, because the digit that carries the meaning moves with the
    /// distance: below a kilometre the metres are the number anybody reads, a
    /// run is read to a tenth of a kilometre, and past 100 km — a training
    /// week, not a session — that tenth is noise next to a three-digit figure.
    ///
    /// A trailing zero is dropped, exactly as `plain` drops it (#186): the
    /// tenth is printed where it carries a digit and left out where it does
    /// not. `"32.0 km"` claims a precision a whole-kilometre figure does not
    /// have, and it put a decimal on both sides of the metric card's
    /// `"32 km → 35 km"` (US-15 AC5). The two forms now state a distance
    /// identically, which is what #181's review round already asked of them
    /// past 100 km.
    ///
    /// `0`, a negative value and a value that is not a finite number (a
    /// corrupted row, never a real distance) read `"0 m"` — the same rule
    /// `ElevationFormatter` and `HeartRateFormatter` follow for their own
    /// units. Whether to show a distance at all is the caller's decision, not
    /// the formatter's.
    static func display(_ meters: Double, locale: Locale = .current) -> String {
        let parts = parts(meters)
        let value = parts.value.formatted(
            .number.precision(.fractionLength(0...parts.decimals)).locale(locale)
        )
        return "\(value) \(parts.unit)"
    }

    /// The same distance as data rather than as display text: `"8.4 km"` on
    /// every device, no grouping separators, no locale-negotiated decimal
    /// comma (#173).
    ///
    /// Used where a distance leaves the app as a value something else reads
    /// back — the analysis prompt — following the rule
    /// `AnalysisPromptBuilder.kg(_:)` follows for weights. Trailing zeros are
    /// dropped by `PlainWeightFormatter`, so `5_000` is `"5 km"`: the model
    /// reads a figure, not a column.
    static func plain(_ meters: Double) -> String {
        let parts = parts(meters)
        return "\(PlainWeightFormatter.string(parts.value, decimals: parts.decimals)) \(parts.unit)"
    }

    /// The distance `display` and `plain` actually print, back in metres:
    /// `32_449` → `32_400`, because both print `"32.4 km"` (#186).
    ///
    /// For a caller that has to compare or subtract two printed distances
    /// rather than print one. A delta taken from the unrounded values can
    /// disagree with the two figures beside it — `32.44 → 35.55` prints
    /// `"32.4 km"` and `"35.6 km"` but differs by `3.11` — and three numbers
    /// on one row that do not add up read as a bug whichever of them is right.
    static func displayedMeters(_ meters: Double) -> Double {
        let parts = parts(meters)
        return parts.unit == "km" ? parts.value * 1_000 : parts.value
    }

    /// The value, its precision and its unit — the one place the ranges are
    /// decided, so the display and the prompt can never pick different ones.
    ///
    /// Metres are rounded before the kilometre threshold is tested: `999.6 m`
    /// is `"1 km"`, never `"1,000 m"`, which would print the threshold's own
    /// unit past it.
    ///
    /// The value is rounded **once**, at the precision it will be printed
    /// with, and always from the exact distance: past 100 km, handing `100.5`
    /// to both callers would leave Foundation's half-even rule to print
    /// `"100 km"` while `PlainWeightFormatter` writes `"101 km"` from the same
    /// distance. The threshold is tested on a copy rounded to a tenth, so
    /// `99.96 km` reads `"100 km"` rather than `"100.0 km"`, but the printed
    /// figure never passes through that tenth — rounding `123.456` to `123.5`
    /// and then to a whole kilometre would report `"124 km"` for a distance
    /// half a kilometre shorter (#186).
    private static func parts(_ meters: Double) -> (value: Double, decimals: Int, unit: String) {
        guard meters > 0, meters.isFinite else { return (0, 0, "m") }
        let wholeMeters = meters.rounded()
        guard wholeMeters >= 1_000 else { return (wholeMeters, 0, "m") }
        let kilometers = meters / 1_000
        guard PlainWeightFormatter.rounded(kilometers, decimals: 1) < 100 else {
            return (PlainWeightFormatter.rounded(kilometers, decimals: 0), 0, "km")
        }
        return (PlainWeightFormatter.rounded(kilometers, decimals: 1), 1, "km")
    }
}
