import SwiftUI

/// Two muscle groups trained at clearly different frequencies, with the
/// app's per-week figures as bars (US-3 AC8, design 3.4, #177).
struct ImbalanceCardView: View {
    let groupA: MuscleGroup
    let perWeekA: Double
    let groupB: MuscleGroup
    let perWeekB: Double
    let reasoning: String

    private var bars: [ImbalanceBar] {
        ImbalanceBar.bars(groupA: groupA, perWeekA: perWeekA, groupB: groupB, perWeekB: perWeekB)
    }

    /// Progress green for the more frequent group, warning orange for the one
    /// the card is about — the order `ImbalanceBar.bars` guarantees.
    private static let colors: [Color] = [.fbAccent, .fbWarn]

    var body: some View {
        FBCard(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    AnalysisCardChip(
                        symbol: "exclamationmark",
                        title: "Imbalance",
                        foreground: .fbInk,
                        background: .fbWarnSoft,
                        border: .fbWarn.opacity(0.25)
                    )
                    Text(AnalysisCardFormatter.imbalanceTitle(bars))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.fbMuted)
                }
                .padding(.bottom, 6)

                Text(AnalysisCardFormatter.imbalanceHeadline(bars))
                    .font(.subheadline.weight(.semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.fbInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(reasoning)
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                HStack(spacing: 8) {
                    ForEach(Array(zip(bars, Self.colors)), id: \.0.group) { bar, color in
                        ImbalanceMuscleTile(bar: bar, color: color)
                    }
                }
                .padding(.top, 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AnalysisCardAccessibility.label(
                for: .imbalance(
                    groupA: groupA,
                    perWeekA: perWeekA,
                    groupB: groupB,
                    perWeekB: perWeekB,
                    reasoning: reasoning
                )
            )
        )
        .accessibilityIdentifier(AccessibilityID.Analysis.imbalanceCard)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 10) {
        ImbalanceCardView(
            groupA: .chest,
            perWeekA: 3,
            groupB: .legs,
            perWeekB: 1,
            reasoning: "Add a second leg session this week (squat or RDL focus) before pushing chest further."
        )
        // Named the other way round by the model: the more frequent group
        // still comes first.
        ImbalanceCardView(
            groupA: .back,
            perWeekA: 0.8,
            groupB: .chest,
            perWeekB: 2.5,
            reasoning: "Match every pressing session with a pull."
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
