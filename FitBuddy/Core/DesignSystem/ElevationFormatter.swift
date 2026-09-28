import Foundation

/// Formats metres of ascent — the elevation gain `#180` adds to an endurance
/// activity (`elevationGainMeters`), on the detail screen and on the endurance
/// cards of the cross-source analysis (US-15, #181).
///
/// Its own formatter rather than `DistanceFormatter`: that one switches to
/// kilometres at 1 km, and `"1.2 km"` of climbing is a figure no training log
/// prints. Ascent stays in metres however high it gets — `"1,200 m"` is what a
/// rider reads, and the grouping separator is what makes it readable.
enum ElevationFormatter {
    /// `340` → `"340 m"`, `1_200` → `"1,200 m"` (grouping follows the locale).
    ///
    /// Whole metres: a barometric altimeter's decimal is noise, and no climb
    /// is read to one.
    ///
    /// `0`, a negative value and a value that is not a finite number read
    /// `"0 m"`, the rule `DistanceFormatter` and `HeartRateFormatter` follow.
    /// A flat session and one whose connector reported no ascent both pass
    /// `nil` further up and show no cell at all (US-15 AC7).
    static func display(_ meters: Double, locale: Locale = .current) -> String {
        ascent(meters).formatted(.number.precision(.fractionLength(0)).locale(locale)) + " m"
    }

    /// The same ascent as data rather than as display text: `"1200 m"` on
    /// every device, no grouping separator — the rule
    /// `AnalysisPromptBuilder.kg(_:)` follows for weights, so the prompt and
    /// the card cannot state a different climb.
    static func plain(_ meters: Double) -> String {
        PlainNumberFormatter.string(ascent(meters), decimals: 0) + " m"
    }

    /// Whole metres of ascent, never below zero and never a value a formatter
    /// would print as `"∞"` or `"inf"`.
    private static func ascent(_ meters: Double) -> Double {
        guard meters > 0, meters.isFinite else { return 0 }
        return PlainNumberFormatter.rounded(meters, decimals: 0)
    }
}
