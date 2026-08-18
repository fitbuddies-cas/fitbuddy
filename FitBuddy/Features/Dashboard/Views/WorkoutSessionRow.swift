import SwiftUI

/// One workout in the dashboard's session list: date and title on the left,
/// volume and set count on the right (US-2 AC1).
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
        .accessibilityElement(children: .combine)
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
