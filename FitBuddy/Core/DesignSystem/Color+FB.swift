import SwiftUI

/// FitBuddy design-system color tokens, ported from `design/fb-atoms.jsx`.
///
/// v0 uses a fixed light palette (warm off-white canvas, white cards) so the
/// app renders identically regardless of the system appearance — the prototype
/// is light-only. The two accent tokens are defined in `oklch` in the design
/// source; here they are the sRGB equivalents (conversion noted inline).
extension Color {
    // Surfaces
    static let fbBackground = Color(hex: 0xF2F1ED) // canvas, warm off-white
    static let fbCard = Color(hex: 0xFFFFFF)
    static let fbCardSubtle = Color(hex: 0xF8F7F4)

    // Ink
    static let fbInk = Color(hex: 0x0E0E0E)
    static let fbInkSecondary = Color(hex: 0x3C3C43)
    static let fbMuted = Color(hex: 0x8A8A8E)
    static let fbTertiary = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: 0.30)
    static let fbBorder = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: 0.10)
    static let fbDivider = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: 0.08)

    // Accent — Progress / training green: oklch(0.62 0.14 150) ≈ sRGB #399D57
    static let fbAccent = Color(hex: 0x399D57)
    static let fbAccentInk = Color(hex: 0x0E2F1F)
    static let fbAccentSoft = Color(hex: 0xE9F5EC) // ≈ oklch(0.95 0.04 150)
    static let fbAccentBorder = Color(hex: 0xBCDFC6) // ≈ oklch(0.85 0.06 150)

    // Accent — Recovery / Warn / warm orange: oklch(0.66 0.16 55) ≈ sRGB #DA720D
    static let fbWarn = Color(hex: 0xDA720D)
    static let fbWarnSoft = Color(hex: 0xF8F0E6) // ≈ oklch(0.96 0.04 65)

    // Status
    static let fbRed = Color(hex: 0xE5484D)
    static let fbRedSoft = Color(hex: 0xFFEFEF)
}

extension Color {
    /// Creates a color from a 24-bit RGB hex literal (e.g. `0xF2F1ED`).
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
