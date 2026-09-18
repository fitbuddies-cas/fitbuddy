import Foundation

/// Formats a heart rate wherever the app shows one — the average and maximum
/// of an endurance session, the endurance cards of the cross-source analysis
/// (US-15, #181).
///
/// The connectors deliver an average as a fraction (`148.4` beats per minute);
/// nobody reads a heart rate to a tenth, so the rounding rule lives here once
/// rather than at each call site.
enum HeartRateFormatter {
    /// `148` → `"148 bpm"`, `148.4` → `"148 bpm"`, `148.5` → `"149 bpm"`.
    ///
    /// Rounded half away from zero by `PlainWeightFormatter`, the rule the
    /// analysis figures already round by, so a card and the prompt behind it
    /// never differ in the last digit. `locale`-aware like the sibling
    /// formatters, although a heart rate stays inside three digits and no
    /// locale will put a separator in it.
    ///
    /// `0` and any negative value read `"0 bpm"`; a session without a heart
    /// rate passes `nil` further up and shows no cell at all (US-15 AC7).
    static func display(_ beatsPerMinute: Double, locale: Locale = .current) -> String {
        let rounded = max(0, PlainWeightFormatter.rounded(beatsPerMinute, decimals: 0))
        return rounded.formatted(.number.precision(.fractionLength(0)).locale(locale)) + " bpm"
    }

    /// The same heart rate as data rather than as display text: `"148 bpm"` on
    /// every device, no grouping separators — the rule
    /// `AnalysisPromptBuilder.kg(_:)` follows for weights.
    static func plain(_ beatsPerMinute: Double) -> String {
        let rounded = max(0, PlainWeightFormatter.rounded(beatsPerMinute, decimals: 0))
        return PlainWeightFormatter.string(rounded, decimals: 0) + " bpm"
    }
}
