import SwiftUI

/// One workout in the dashboard's session list: date and title on the left,
/// the session's headline figure and a detail on the right (US-2 AC1).
///
/// Since #144 the list holds two kinds of session. A strength session reads
/// as volume and sets; a cardio one — a Strava run, or Hevy treadmill sets —
/// has no kg to show and reads as distance and time instead. Sessions from a
/// second source carry a badge, so the two providers can be told apart in one
/// chronological list (US-5 AC1).
///
/// Presentational only — `RecentSessionsCard` wraps it in the `NavigationLink`
/// that opens the detail screen (#98). The row spells its own accessibility
/// label out rather than leaving it to `.combine`, so the announcement is a
/// sentence and not the fragments the layout happens to be built from.
struct WorkoutSessionRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.startTime, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(Color.fbMuted)
                HStack(spacing: 6) {
                    Text(workout.title)
                        .font(.subheadline)
                        .foregroundStyle(Color.fbInk)
                        .lineLimit(1)
                    if workout.source != .hevy {
                        sourceBadge
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(headline)
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
        // The whole row is the tap target, not just the labels in it: a link
        // only hit-tests what it actually draws, so without this the spacer
        // between the two columns and the padding around them are dead areas
        // — and that gap is most of the row.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Only sessions from a second source are badged: Hevy is where every
    /// session came from before US-5, and badging all of them would say
    /// nothing. Design-system tokens only, no colour of its own.
    private var sourceBadge: some View {
        Text(workout.source.displayName.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Color.fbInkSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.fbCardSubtle)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.fbBorder, lineWidth: 1))
            .accessibilityIdentifier(AccessibilityID.Dashboard.sourceBadge)
    }

    // MARK: - Figures

    /// Volume for a strength session; distance, or failing that time, for a
    /// cardio one. "0 kg" for a run would be a wrong number, not a missing one.
    private var headline: String {
        guard workout.isCardio else { return "\(VolumeFormatter.full(workout.volumeKg)) kg" }
        return SetMetricFormatter.distance(workout.distanceMeters)
            ?? SetMetricFormatter.duration(workout.durationSeconds)
            ?? "–"
    }

    private var detail: String {
        guard workout.isCardio else {
            let sets = CountFormatter.labelled(workout.countedSetCount, singular: "set")
            let exercises = CountFormatter.labelled(workout.exerciseCount, singular: "exercise")
            return "\(sets) · \(exercises)"
        }
        // The time goes in the detail line only when the distance took the
        // headline; otherwise it is the headline already.
        if workout.distanceMeters != nil, let duration = SetMetricFormatter.duration(workout.durationSeconds) {
            return duration
        }
        return "cardio"
    }

    private var accessibilityLabel: String {
        let date = workout.startTime.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let origin = workout.source == .hevy ? "" : " from \(workout.source.displayName)"
        return "\(workout.title)\(origin), \(date), \(headline), \(detail)"
    }
}

#Preview {
    VStack(spacing: 0) {
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
        Divider()
        WorkoutSessionRow(
            workout: WorkoutSummary(
                id: "strava:2",
                title: "Morning Run",
                startTime: .now.addingTimeInterval(-86_400),
                source: .strava,
                volumeKg: 0,
                exerciseCount: 1,
                countedSetCount: 1,
                distanceMeters: 5_240,
                durationSeconds: 1_712
            )
        )
    }
    .background(Color.fbCard)
}
