import SwiftUI

/// Rest before any progression, with the app's own figures for the last
/// seven days (US-14 AC4, US-3 AC6, design 3.5, #177).
struct RecoveryCardView: View {
    let reasoning: String
    let metrics: RecoveryMetrics

    var body: some View {
        FBCard(padding: 16, background: .fbWarnSoft, border: .fbWarn.opacity(0.25)) {
            VStack(alignment: .leading, spacing: 0) {
                AnalysisCardChip(
                    symbol: "pause.fill",
                    title: "Recovery",
                    foreground: .fbWarn,
                    background: .fbCard,
                    border: .fbWarn.opacity(0.25)
                )
                .padding(.bottom, 6)

                Text(AnalysisCardFormatter.recoveryHeadline(metrics))
                    .font(.fbTitle)
                    .tracking(-0.3)
                    .foregroundStyle(Color.fbInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(reasoning)
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                HStack(alignment: .top, spacing: 10) {
                    ForEach(RecoveryMetricCell.cells(for: metrics), id: \.label) { cell in
                        FBStat(label: cell.label, value: cell.value, size: .compact)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(Color.fbCard, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AnalysisCardAccessibility.label(for: .recovery(reasoning: reasoning, metrics: metrics)))
        .accessibilityIdentifier(AccessibilityID.Analysis.recoveryCard)
    }
}

#if DEBUG
#Preview("With RPE") {
    RecoveryCardView(
        reasoning: """
            Before adding load to chest or legs, take two rest days and one deload \
            session at ~60 % of your usual sets.
            """,
        metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2)
    )
    .padding(16)
    .background(Color.fbBackground)
}

/// No set in the week logged an RPE: the cell is gone, not a "—".
#Preview("Without RPE") {
    RecoveryCardView(
        reasoning: "Take two rest days before the next heavy session.",
        metrics: RecoveryMetrics(sessions: 7, trainingDays: 7, averageRPE: nil)
    )
    .padding(16)
    .background(Color.fbBackground)
}
#endif
