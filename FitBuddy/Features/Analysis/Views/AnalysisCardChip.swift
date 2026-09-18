import SwiftUI

/// The small capsule at the top of a report card that names its kind —
/// "↑ INCREASE", "⏸ RECOVERY", "! IMBALANCE" (design 3.4/3.5, #177).
///
/// The glyph is an SF Symbol rather than the mock's text character, so it
/// sits on the text's baseline and scales with it.
struct AnalysisCardChip: View {
    let symbol: String
    let title: String
    let foreground: Color
    let background: Color
    let border: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.2)
        }
        .foregroundStyle(foreground)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 12) {
        AnalysisCardChip(
            symbol: "arrow.up",
            title: "Increase",
            foreground: .fbAccentInk,
            background: .fbAccentSoft,
            border: .fbAccentBorder
        )
        AnalysisCardChip(
            symbol: "pause.fill",
            title: "Recovery",
            foreground: .fbWarn,
            background: .fbCard,
            border: .fbWarn.opacity(0.25)
        )
        AnalysisCardChip(
            symbol: "exclamationmark",
            title: "Imbalance",
            foreground: .fbInk,
            background: .fbWarnSoft,
            border: .fbWarn.opacity(0.25)
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
