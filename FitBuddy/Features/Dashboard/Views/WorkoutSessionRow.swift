import SwiftUI

/// One workout in the dashboard's session list: date and title on the left,
/// volume and set count on the right (US-2 AC1).
///
/// Presentational only — `RecentSessionsCard` wraps it in the `NavigationLink`
/// that opens the detail screen (#98). The row spells its own accessibility
/// label out rather than leaving it to `.combine`, so the announcement is a
/// sentence and not the four fragments the layout happens to be built from.
struct WorkoutSessionRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.startTime, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(Color.fbMuted)
                Text(workout.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(VolumeFormatter.full(workout.volumeKg)) kg")
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
        // The whole row is the tap target, not just the four labels in it: a
        // link only hit-tests what it actually draws, so without this the
        // spacer between the two columns and the padding around them are dead
        // areas — and that gap is most of the row.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let date = workout.startTime.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "\(workout.title), \(date), \(VolumeFormatter.full(workout.volumeKg)) kg, \(detail)"
    }

    private var detail: String {
        let sets = CountFormatter.labelled(workout.countedSetCount, singular: "set")
        let exercises = CountFormatter.labelled(workout.exerciseCount, singular: "exercise")
        return "\(sets) · \(exercises)"
    }
}

#Preview {
    WorkoutSessionRow(
        workout: WorkoutSummary(
            id: "1",
            title: "Push Day",
            startTime: .now,
            volumeKg: 8_420,
            exerciseCount: 6,
            countedSetCount: 21
        )
    )
    .background(Color.fbCard)
}
