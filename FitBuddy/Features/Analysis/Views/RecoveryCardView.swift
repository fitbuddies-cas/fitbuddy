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

                let cells = RecoveryMetricCell.cells(for: metrics)
                // A mixed week that logged both an RPE and a heart rate fills
                // four columns where design 3.5 drew three, so the gap gives
                // way before the labels do (#184). `FBStat.compact` already
                // keeps a label on one line and scales it down.
                HStack(alignment: .top, spacing: cells.count > 3 ? 8 : 10) {
                    ForEach(cells, id: \.label) { cell in
                        FBStat(label: cell.label, value: cell.value, unit: cell.unit, size: .compact)
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

/// Four strength sessions and two runs on six days (#184): the count spans
/// both domains, and the week logged both means, so the row is four cells wide.
#Preview("Mixed week") {
    RecoveryCardView(
        reasoning: "Four strength sessions and two runs on six days leave no day for adaptation.",
        metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2, averageHeartRate: 148)
    )
    .padding(16)
    .background(Color.fbBackground)
}

/// Runs only: nothing logged an RPE, the strap recorded a heart rate.
#Preview("Endurance only") {
    RecoveryCardView(
        reasoning: "Six running days in a row: take a rest day before the next hard session.",
        metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil, averageHeartRate: 151)
    )
    .padding(16)
    .background(Color.fbBackground)
}
#endif
