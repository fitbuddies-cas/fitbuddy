import Foundation

/// Rounds a number to a given count of fraction digits and writes it without
/// any locale: `60`, `62.5`, `61.25` — a period as decimal mark, no grouping
/// separators, no trailing zeros, the same on every device (#173, #249).
///
/// For figures that leave the app as data something else reads back: the
/// analysis prompt, and the check of the model's answer against it (#175).
/// Both have to agree on the exact figure, so the rounding rule lives here
/// once — weights, and via `DistanceFormatter`, `HeartRateFormatter` and
/// `ElevationFormatter` distances, heart rates and elevation gains.
///
/// Not for on-screen text: `OneRepMaxFormatter` follows the device locale and
/// writes `62,5` on a Swiss device, which is right on screen and wrong in a
/// prompt.
enum PlainNumberFormatter {
    /// Fraction digits kept when the caller names none. Two, because a
    /// working weight comes in 1.25 kg plate pairs, and `61.3` would be a
    /// weight nobody can load.
    static let defaultDecimals = 2

    /// `value` rounded half away from zero to `decimals` places.
    static func rounded(_ value: Double, decimals: Int = defaultDecimals) -> Double {
        let factor = pow(10, Double(decimals))
        return (value * factor).rounded() / factor
    }

    /// `value` rounded to `decimals` places, trailing zeros dropped.
    static func string(_ value: Double, decimals: Int = defaultDecimals) -> String {
        // `String(format:)` without a locale always writes a period.
        let text = String(format: "%.\(decimals)f", rounded(value, decimals: decimals))
        guard text.contains(".") else { return text }
        let trimmed = text.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
    }
}
