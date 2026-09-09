import SwiftUI

/// One movement in the exercise list: muscle group and title on the left, its
/// window totals on the right (US-7, #37).
///
/// Presentational only, like `WorkoutSessionRow` — and it spells its own
/// accessibility label out for the same reason: the announcement should be a
/// sentence, not the fragments the layout is built from.
struct ExerciseSummaryRow: View {
    let exercise: ExerciseSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.muscleGroup.displayName.uppercased())
                    .font(.fbLabel)
                    .tracking(0.6)
                    .foregroundStyle(Color.fbMuted)
                Text(exercise.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(volume)
                    .font(.subheadline.weight(.semibold))
                    .fbTabularNumbers()
                    .foregroundStyle(Color.fbInk)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Color.fbMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Bodyweight and cardio movements produce no kg over the whole window, and
    /// a bold "0 kg" would read as a result rather than as the absence of one.
    /// Their sets say what actually happened, so the volume slot shows those.
    private var volume: String {
        guard exercise.volumeKg > 0 else {
            return CountFormatter.labelled(exercise.countedSetCount, singular: "set")
        }
        return "\(VolumeFormatter.full(exercise.volumeKg)) kg"
    }

    private var detail: String {
        let sessions = CountFormatter.labelled(exercise.sessionCount, singular: "session")
        let last = exercise.lastPerformed.formatted(.dateTime.day().month(.abbreviated))
        return "\(sessions) · last \(last)"
    }

    private var accessibilityLabel: String {
        let last = exercise.lastPerformed.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let sessions = CountFormatter.labelled(exercise.sessionCount, singular: "session")
        return "\(exercise.title), \(exercise.muscleGroup.displayName), \(volume), \(sessions), last performed \(last)"
    }
}

#Preview {
    ExerciseSummaryRow(
        exercise: ExerciseSummary(
            id: "1",
            title: "Bench Press (Barbell)",
            muscleGroup: .chest,
            sessionCount: 9,
            countedSetCount: 34,
            volumeKg: 42_180,
            lastPerformed: .now
        )
    )
    .background(Color.fbCard)
}
