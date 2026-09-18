import SwiftUI

/// A load increase on one exercise: from the cache's working weight to the
/// model's target (US-14 AC2, design 3.4, #177).
struct ProgressionCardView: View {
    let exercise: String
    let muscleGroup: MuscleGroup
    let fromKg: Double
    let toKg: Double
    let reasoning: String

    var body: some View {
        FBCard(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    AnalysisCardChip(
                        symbol: "arrow.up",
                        title: "Increase",
                        foreground: .fbAccentInk,
                        background: .fbAccentSoft,
                        border: .fbAccentBorder
                    )
                    Text(muscleGroup.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.fbMuted)
                }
                .padding(.bottom, 6)

                Text(exercise)
                    .font(.fbTitle)
                    .tracking(-0.3)
                    .foregroundStyle(Color.fbInk)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AnalysisCardFormatter.weight(fromKg))
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundStyle(Color.fbMuted)
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.fbMuted)
                    Text(AnalysisCardFormatter.weight(toKg))
                        .font(.title2.weight(.bold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.fbAccent)
                    Spacer(minLength: 8)
                    Text(AnalysisCardFormatter.delta(fromKg: fromKg, toKg: toKg))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.fbMuted)
                }
                .fbTabularNumbers()
                .padding(.top, 10)

                Divider()
                    .overlay(Color.fbDivider)
                    .padding(.top, 10)

                Text(reasoning)
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AnalysisCardAccessibility.label(
                for: .progression(
                    exercise: exercise,
                    muscleGroup: muscleGroup,
                    fromKg: fromKg,
                    toKg: toKg,
                    reasoning: reasoning
                )
            )
        )
        .accessibilityIdentifier(AccessibilityID.Analysis.progressionCard)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 10) {
        ProgressionCardView(
            exercise: "Bench Press (Barbell)",
            muscleGroup: .chest,
            fromKg: 60,
            toKg: 62.5,
            reasoning: "3 sessions at 60×5 with RPE ≤7 — clean overload signal."
        )
        ProgressionCardView(
            exercise: "Lateral Raise (Dumbbell)",
            muscleGroup: .shoulders,
            fromKg: 8.75,
            toKg: 10,
            reasoning: "Twelve clean reps on every set for three sessions."
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
