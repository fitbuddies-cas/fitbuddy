import SwiftUI

/// FitBuddy typography helpers. The design system uses the system font (SF Pro)
/// with tabular numerals on all numeric values so stats and figures align.
extension Font {
    /// Large numeric value used in stat cards (bold). Anchored to the
    /// `.largeTitle` text style so it scales with Dynamic Type.
    static let fbStatValue = Font.system(.largeTitle).weight(.bold)
    /// Section / card title (17 pt, semibold). `.headline` is 17 pt semibold
    /// and scales with Dynamic Type.
    static let fbTitle = Font.headline
    /// Uppercase label above stats and sections (medium). Anchored to the
    /// `.caption` text style so it scales with Dynamic Type.
    static let fbLabel = Font.system(.caption).weight(.medium)
}

extension View {
    /// Applies tabular (monospaced) digits so numbers keep a fixed width.
    func fbTabularNumbers() -> some View {
        monospacedDigit()
    }
}
