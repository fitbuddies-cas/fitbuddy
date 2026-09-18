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
    /// `850` → `"850 m"`, `8_400` → `"8.4 km"`, `104_300` → `"104 km"`.
    ///
    /// Three ranges, because the digit that carries the meaning moves with the
    /// distance: below a kilometre the metres are the number anybody reads, a
    /// run is read to a tenth of a kilometre, and past 100 km — a training
    /// week, not a session — that tenth is noise next to a three-digit figure.
    ///
    /// `0`, a negative value and a value that is not a finite number (a
    /// corrupted row, never a real distance) read `"0 m"` — the same rule
    /// `ElevationFormatter` and `HeartRateFormatter` follow for their own
    /// units. Whether to show a distance at all is the caller's decision, not
    /// the formatter's.
    static func display(_ meters: Double, locale: Locale = .current) -> String {
        let parts = parts(meters)
        let value = parts.value.formatted(
            .number.precision(.fractionLength(parts.decimals)).locale(locale)
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

    /// The value, its precision and its unit — the one place the ranges are
    /// decided, so the display and the prompt can never pick different ones.
    ///
    /// Metres are rounded before the kilometre threshold is tested: `999.6 m`
    /// is `"1.0 km"`, never `"1,000 m"`, which would print the threshold's own
    /// unit past it.
    ///
    /// The value is rounded once, at the precision it will be printed with:
    /// past 100 km, handing `100.5` to both callers would leave Foundation's
    /// half-even rule to print `"100 km"` while `PlainWeightFormatter` writes
    /// `"101 km"` from the same distance.
    private static func parts(_ meters: Double) -> (value: Double, decimals: Int, unit: String) {
        guard meters > 0, meters.isFinite else { return (0, 0, "m") }
        let wholeMeters = meters.rounded()
        guard wholeMeters >= 1_000 else { return (wholeMeters, 0, "m") }
        let kilometers = PlainWeightFormatter.rounded(meters / 1_000, decimals: 1)
        guard kilometers < 100 else {
            return (PlainWeightFormatter.rounded(kilometers, decimals: 0), 0, "km")
        }
        return (kilometers, 1, "km")
    }
}
