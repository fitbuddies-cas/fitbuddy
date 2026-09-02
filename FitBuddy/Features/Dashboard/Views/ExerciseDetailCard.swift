import SwiftUI

/// One exercise of a session: its title, muscle group, the user's note and
/// every set they logged (#98).
struct ExerciseDetailCard: View {
    let exercise: ExerciseDetail
    /// Total volume of the session, so the bar can show this exercise's share
    /// of it. `0` for an all-bodyweight session, where there is no share to
    /// draw.
    let sessionVolumeKg: Double

    var body: some View {
        FBCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let notes = exercise.notes, !notes.isEmpty {
                    note(notes)
                }
                share
                Divider().overlay(Color.fbDivider)
                sets
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.muscleGroup.displayName.uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(exercise.title)
                    .font(.fbTitle)
                    .foregroundStyle(Color.fbInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Only when Hevy grouped this exercise with another: on its
                // own the number means nothing, and the label would be one
                // more badge on every card.
                if let supersetID = exercise.supersetID {
                    Text("Superset \(supersetID)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.fbAccentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.fbAccentSoft)
                        .clipShape(Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ notes: String) -> some View {
        Text(notes)
            .font(.caption)
            .foregroundStyle(Color.fbInkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.fbCardSubtle)
            .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
    }

    /// What this exercise contributed to the session, as a share of its total
    /// volume — or just the counted sets when the session produced no kg at
    /// all (bodyweight, cardio), where every bar would be empty.
    @ViewBuilder
    private var share: some View {
        if sessionVolumeKg > 0 {
            FBBar(
                label: CountFormatter.labelled(exercise.countedSetCount, singular: "set"),
                fraction: exercise.volumeKg / sessionVolumeKg,
                value: VolumeFormatter.compact(exercise.volumeKg)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shareAccessibilityLabel)
        } else {
            Text(CountFormatter.labelled(exercise.countedSetCount, singular: "counted set"))
                .font(.caption)
                .foregroundStyle(Color.fbMuted)
        }
    }

    private var shareAccessibilityLabel: String {
        let sets = CountFormatter.labelled(exercise.countedSetCount, singular: "counted set")
        return "\(sets), \(VolumeFormatter.full(exercise.volumeKg)) kg"
    }

    /// The logged sets in Hevy's order. Warm-ups are shown but not numbered —
    /// `SetDetailRow` marks them, and they do not count towards the volume
    /// above.
    private var sets: some View {
        VStack(spacing: 0) {
            ForEach(numberedSets, id: \.set.id) { entry in
                SetDetailRow(set: entry.set, number: entry.number)
            }
        }
    }

    /// Pairs each set with its number among the counted ones, so the rows read
    /// "W, 1, 2, 3" the way the app tallies them — not "1, 2, 3, 4" with the
    /// warm-up quietly claiming a working set's place.
    private var numberedSets: [(set: SetDetail, number: Int)] {
        var number = 0
        return exercise.sets.map { set in
            if set.countsTowardsVolume { number += 1 }
            return (set, number)
        }
    }
}

#if DEBUG
#Preview("Barbell") {
    ScrollView {
        ExerciseDetailCard(
            exercise: PreviewWorkoutDetailCache.session.exercises[0],
            sessionVolumeKg: PreviewWorkoutDetailCache.session.volumeKg
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}

#Preview("Bodyweight & cardio") {
    ScrollView {
        VStack(spacing: 12) {
            ExerciseDetailCard(
                exercise: PreviewWorkoutDetailCache.session.exercises[2],
                sessionVolumeKg: 0
            )
            ExerciseDetailCard(
                exercise: PreviewWorkoutDetailCache.session.exercises[3],
                sessionVolumeKg: 0
            )
        }
        .padding(16)
    }
    .background(Color.fbBackground)
}
#endif
