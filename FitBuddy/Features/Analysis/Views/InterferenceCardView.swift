import SwiftUI

/// How strength and endurance sat in the same week (US-15 AC2, design 3.4d,
/// #186).
///
/// The one card neither domain could have produced on its own. "Four strength
/// days" and "four running days" describe a week of eight sessions on eight
/// days just as well as a week of four doubles, and the two call for opposite
/// advice.
///
/// Orange like the recovery card, because it warns rather than adds — and,
/// like the recovery card, every figure on it is the app's own count over the
/// last seven days. Only the sentence is the model's.
struct InterferenceCardView: View {
    let metrics: InterferenceMetrics
    let reasoning: String

    var body: some View {
        FBCard(padding: 16, background: .fbWarnSoft, border: .fbWarn.opacity(0.25)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    AnalysisCardChip(
                        symbol: "arrow.left.arrow.right",
                        title: "Interference",
                        foreground: .fbWarn,
                        background: .fbCard,
                        border: .fbWarn.opacity(0.25)
                    )
                    Spacer(minLength: 8)
                    Text("Strength + endurance")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.fbMuted)
                }
                .padding(.bottom, 6)

                Text(AnalysisCardFormatter.interferenceHeadline(metrics))
                    .font(.fbTitle)
                    .tracking(-0.3)
                    .foregroundStyle(Color.fbInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(reasoning)
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                // Three cells, always all three — unlike the recovery card,
                // whose RPE and heart rate drop out where nothing recorded
                // them. A zero here is a count the app made ("no day carried
                // both"), which is a finding rather than a missing
                // measurement, so AC7 does not apply to it.
                HStack(alignment: .top, spacing: 10) {
                    ForEach(AnalysisCardFormatter.interferenceCells(metrics), id: \.label) { cell in
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
        .accessibilityLabel(
            AnalysisCardAccessibility.label(for: .interference(metrics: metrics, reasoning: reasoning))
        )
        .accessibilityIdentifier(AccessibilityID.Analysis.interferenceCard)
    }
}

#if DEBUG
#Preview("Overlapping week") {
    InterferenceCardView(
        metrics: InterferenceMetrics(strengthDays: 4, cardioDays: 4, overlapDays: 3),
        reasoning: """
            Move one run onto a day without lifting — the overlap costs you \
            more than the extra session gains.
            """
    )
    .padding(16)
    .background(Color.fbBackground)
}

/// Both domains in the week, never on the same day: the card's other finding.
#Preview("No overlap") {
    InterferenceCardView(
        metrics: InterferenceMetrics(strengthDays: 3, cardioDays: 3, overlapDays: 0),
        reasoning: "Six training days with no rest between them — the split is clean, the week is not."
    )
    .padding(16)
    .background(Color.fbBackground)
}
#endif
