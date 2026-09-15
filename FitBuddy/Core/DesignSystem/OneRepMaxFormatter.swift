import Foundation

/// Formats an estimated one-rep max wherever the app shows one (US-9, #42).
///
/// Its own formatter rather than `VolumeFormatter`: volumes run into the
/// hundreds of thousands and are rounded to whole kilograms because nobody
/// reads the last digit of `248,420`. A 1RM is a two- or three-digit number
/// whose *half* kilograms carry the meaning — plates come in 1.25 kg pairs, a
/// mesocycle moves the estimate by a few kilos, and rounding 107.5 to 108
/// throws away exactly the step the screen exists to show.
enum OneRepMaxFormatter {
    /// `107.5` → `107.5`, `100` → `100`, `102.25` → `102.3`.
    ///
    /// One decimal at most: the estimate is a projection, and a second decimal
    /// would claim a precision Epley does not have.
    static func kilograms(_ kilograms: Double) -> String {
        kilograms.formatted(.number.precision(.fractionLength(0...1)))
    }
}
