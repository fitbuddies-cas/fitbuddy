import SwiftUI

/// More repetitions at the cache's working weight on one exercise (US-17
/// AC3, design 3.4e, #234) — the progression card's sibling for the movements
/// the 2-for-2 rule holds back or whose equipment offers no fitting step.
///
/// Laid out like `ProgressionCardView`, so the two read as one family: chip
/// and muscle group, the exercise, the struck-through figure and the target,
/// the delta on the right. The weight that stays is the line under the reps
/// — it is the one number on the card that does not move, and putting it in
/// the figure row would make it read as a target.
struct RepProgressionCardView: View {
    let exercise: String
    let muscleGroup: MuscleGroup
    let weightKg: Double
    let fromReps: Int
    let toReps: Int
    let reasoning: String

    var body: some View {
        FBCard(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    AnalysisCardChip(
                        symbol: "arrow.up",
                        title: "More reps",
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
                    Text(AnalysisCardFormatter.reps(fromReps))
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundStyle(Color.fbMuted)
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.fbMuted)
                    Text(AnalysisCardFormatter.reps(toReps))
                        .font(.title2.weight(.bold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.fbAccent)
                    Spacer(minLength: 8)
                    Text(AnalysisCardFormatter.repDelta(fromReps: fromReps, toReps: toReps))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.fbMuted)
                }
                .fbTabularNumbers()
                .padding(.top, 10)

                Text(AnalysisCardFormatter.atWeight(weightKg))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.fbMuted)
                    .fbTabularNumbers()
                    .padding(.top, 4)

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
                for: .repProgression(
                    exercise: exercise,
                    muscleGroup: muscleGroup,
                    weightKg: weightKg,
                    fromReps: fromReps,
                    toReps: toReps,
                    reasoning: reasoning
                )
            )
        )
        .accessibilityIdentifier(AccessibilityID.Analysis.repProgressionCard)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 10) {
        RepProgressionCardView(
            exercise: "Lateral Raise (Dumbbell)",
            muscleGroup: .shoulders,
            weightKg: 10,
            fromReps: 12,
            toReps: 14,
            reasoning: "Twelve clean reps for three sessions and the next dumbbell is a 20 % jump — earn it with reps first."
        )
        RepProgressionCardView(
            exercise: "Bent Over Row (Barbell)",
            muscleGroup: .back,
            weightKg: 50,
            fromReps: 8,
            toReps: 9,
            reasoning: "Eight reps twice at the target — one more before the bar goes up."
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
