import SwiftUI

/// One exercise of a session: its title, muscle group, the user's note and
/// every set they logged (#98).
struct ExerciseDetailCard: View {
    let exercise: ExerciseDetail
    /// Total volume of the session — the denominator the bar draws this
    /// exercise's share against.
    let sessionVolumeKg: Double

    var body: some View {
        FBCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let notes = exercise.notes, !notes.isEmpty {
                    note(notes)
                }
                share
                // Only with something under it: an exercise created in Hevy
                // but never logged has no sets, and the card would end on a
                // free-standing rule.
                if !exercise.sets.isEmpty {
                    Divider().overlay(Color.fbDivider)
                    sets
                }
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
    /// volume — or just the counted sets when *this* exercise produced no kg
    /// (bodyweight, cardio), where the bar would be an empty rail labelled 0.
    ///
    /// The exercise decides, not the session: in a mixed session the session
    /// total is greater than zero while the dips in it are still weightless.
    ///
    /// The session total is checked all the same, because a share of zero is
    /// not a share: Hevy logs assisted machines with a negative `weight_kg`,
    /// so a session can total zero while an exercise in it counted volume. The
    /// division would then be infinite or NaN, and the set count says more
    /// than a bar of an undefined length.
    @ViewBuilder
    private var share: some View {
        if exercise.volumeKg > 0, sessionVolumeKg > 0 {
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

    /// The logged sets in Hevy's order. Sets outside the volume are shown but
    /// not numbered — `SetDetailRow` marks them instead. The numbering itself
    /// belongs to `ExerciseDetail`, so it can be tested without a view.
    private var sets: some View {
        VStack(spacing: 0) {
            ForEach(exercise.numberedSets, id: \.set.id) { entry in
                SetDetailRow(set: entry.set, number: entry.number)
            }
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

/// Two weightless exercises inside a session that *does* have volume — the
/// mixed case, where the bar has to give way to the plain set count.
#Preview("Bodyweight & cardio") {
    ScrollView {
        VStack(spacing: 12) {
            ExerciseDetailCard(
                exercise: PreviewWorkoutDetailCache.session.exercises[2],
                sessionVolumeKg: PreviewWorkoutDetailCache.session.volumeKg
            )
            ExerciseDetailCard(
                exercise: PreviewWorkoutDetailCache.session.exercises[3],
                sessionVolumeKg: PreviewWorkoutDetailCache.session.volumeKg
            )
        }
        .padding(16)
    }
    .background(Color.fbBackground)
}
#endif
