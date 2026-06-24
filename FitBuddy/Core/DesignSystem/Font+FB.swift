import SwiftUI

/// FitBuddy typography helpers. The design system uses the system font (SF Pro)
/// with tabular numerals on all numeric values so stats and figures align.
extension Font {
    /// Large numeric value used in stat cards (32 pt, bold).
    static let fbStatValue = Font.system(size: 32, weight: .bold)
    /// Section / card title (17 pt, semibold).
    static let fbTitle = Font.system(size: 17, weight: .semibold)
    /// Uppercase label above stats and sections (12 pt, medium).
    static let fbLabel = Font.system(size: 12, weight: .medium)
}

extension View {
    /// Applies tabular (monospaced) digits so numbers keep a fixed width.
    func fbTabularNumbers() -> some View {
        monospacedDigit()
    }
}
