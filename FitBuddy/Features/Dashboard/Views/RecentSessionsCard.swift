import SwiftUI

/// Every workout of the 90-day window (US-2 AC1).
///
/// Renders the whole window rather than capping the list: the sessions are
/// already local in the `WorkoutStore` after a sync, so more rows cost no
/// network access, and the header's "N total" already states the count.
///
/// Each row pushes the workout detail screen (#98) by value rather than by
/// destination view: `.navigationDestination(for: WorkoutSummary.self)` on the
/// dashboard builds that screen's ViewModel once per push, whereas the closure
/// form would build one per rendered row.
struct RecentSessionsCard: View {
    let workouts: [WorkoutSummary]

    var body: some View {
        FBCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    if index > 0 {
                        Divider().overlay(Color.fbDivider)
                    }
                    NavigationLink(value: workout) {
                        WorkoutSessionRow(workout: workout)
                    }
                    // Keeps the row's own styling: the default link tint would
                    // repaint the date and the volume in accent blue.
                    .buttonStyle(.plain)
                    // `.plain` also costs the announcement: without this
                    // VoiceOver reads the row as a button, and the user has no
                    // way to tell it opens a screen.
                    .accessibilityAddTraits(.isLink)
                    .accessibilityIdentifier(AccessibilityID.Dashboard.sessionRow)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recent sessions".uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            Spacer()
            Text("\(workouts.count) total")
                .font(.caption2)
                .foregroundStyle(Color.fbMuted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

#Preview {
    NavigationStack {
        RecentSessionsCard(
            workouts: (0..<14).map { index in
                WorkoutSummary(
                    id: "\(index)",
                    title: index.isMultiple(of: 2) ? "Push Day" : "Leg Day",
                    startTime: .now.addingTimeInterval(Double(-index) * 86_400),
                    volumeKg: 8_420 - Double(index) * 120,
                    exerciseCount: 6,
                    countedSetCount: 21
                )
            }
        )
        .padding()
        .background(Color.fbBackground)
    }
}
