import SwiftUI

/// One workout in the dashboard's session list: date and title on the left,
/// the session's headline figure and a detail on the right (US-2 AC1).
///
/// Since #144 the list holds two kinds of session. A strength session reads
/// as volume and sets; a cardio one — a Strava run, or Hevy treadmill sets —
/// has no kg to show and reads as distance and time instead. Every session
/// carries a badge naming its source, tinted per provider — Strava in the
/// design system's orange, Hevy in ink — so the two can be told apart at a
/// glance in one chronological list (US-5 AC1).
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
                // Date and source share the caption line: both say where and
                // when the session comes from, and the title keeps its full
                // width below.
                HStack(spacing: 6) {
                    Text(workout.startTime, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.caption)
                        .foregroundStyle(Color.fbMuted)
                    sourceBadge
                }
                Text(workout.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInk)
                    .lineLimit(1)
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

    /// The source, as a small filled capsule after the date. Same pairings as
    /// the design system's buttons: Strava on the warm orange and Polar on the
    /// red, both with white text, echoing their logos; Hevy as ink with the background colour as text, like
    /// `.primary` — black with light text on the light theme, and the reverse
    /// on the dark one, where a white badge with white text would vanish.
    private var sourceBadge: some View {
        Text(workout.source.displayName.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(badgeText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeFill)
            .clipShape(Capsule())
            .accessibilityIdentifier(AccessibilityID.Dashboard.sourceBadge)
    }

    private var badgeFill: Color {
        switch workout.source {
        case .strava: return .fbWarn
        case .polar: return .fbRed
        case .hevy: return .fbInk
        }
    }

    private var badgeText: Color {
        switch workout.source {
        case .strava, .polar: return .white
        case .hevy: return .fbBackground
        }
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

    /// Names the source for every row, as the badge does.
    private var accessibilityLabel: String {
        let date = workout.startTime.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "\(workout.title) from \(workout.source.displayName), \(date), \(headline), \(detail)"
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
