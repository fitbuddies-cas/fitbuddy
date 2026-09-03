import Foundation

/// Formats training volumes for the dashboard.
///
/// Volumes span four orders of magnitude — a single session is thousands of
/// kilograms, a 90-day window hundreds of thousands — so the full form carries
/// grouping separators and the compact form is what fits next to a chart bar.
enum VolumeFormatter {
    /// `248420` → `248,420` (grouping follows the device locale).
    static func full(_ kilograms: Double) -> String {
        kilograms.formatted(.number.precision(.fractionLength(0)))
    }

    /// `46320` → `46k`, `4820` → `4.8k`, `640` → `640`.
    ///
    /// At most one decimal below 10k and none above: `46.3k` next to a bar is
    /// noise, while `4k` would round two very different sessions to the same
    /// label.
    static func compact(_ kilograms: Double) -> String {
        guard kilograms >= 1_000 else {
            return kilograms.formatted(.number.precision(.fractionLength(0)))
        }
        let thousands = kilograms / 1_000
        let digits = thousands < 10 ? 0...1 : 0...0
        return thousands.formatted(.number.precision(.fractionLength(digits))) + "k"
    }
}
