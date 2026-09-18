import Foundation

/// Writes a weight as data rather than as display text: `60`, `62.5`,
/// `61.25` — no grouping separators, no trailing zeros, the same on every
/// device (#173).
///
/// Used where a weight leaves the app as a value something else reads back:
/// the analysis prompt, and the check of the model's answer against it
/// (#175). Both have to agree on the exact figure, so the rounding lives here
/// once rather than in each of them.
///
/// Not `OneRepMaxFormatter`: that one follows the device locale and would
/// write `62,5` on a Swiss device, which is right on screen and wrong in a
/// prompt.
enum PlainWeightFormatter {
    /// Decimals a working weight keeps. Two, because plates come in 1.25 kg
    /// pairs, and `61.3` would be a weight nobody can load.
    static let weightDecimals = 2

    /// `kilograms` rounded half away from zero to `decimals` places.
    static func rounded(_ kilograms: Double, decimals: Int = weightDecimals) -> Double {
        let factor = pow(10, Double(decimals))
        return (kilograms * factor).rounded() / factor
    }

    /// `kilograms` rounded to `decimals` places, trailing zeros dropped.
    static func string(_ kilograms: Double, decimals: Int = weightDecimals) -> String {
        // `String(format:)` without a locale always writes a period.
        let text = String(format: "%.\(decimals)f", rounded(kilograms, decimals: decimals))
        guard text.contains(".") else { return text }
        let trimmed = text.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
    }
}
