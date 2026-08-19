import SwiftUI

/// The window's most recent workouts (US-2 AC1).
///
/// Caps the list instead of rendering all 90 days: the dashboard is a summary,
/// and the full history needs a screen of its own rather than an endless card.
struct RecentSessionsCard: View {
    let workouts: [WorkoutSummary]
    /// Rows rendered before the "+ n more" footer.
    var limit: Int = 10

    var body: some View {
        FBCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(visibleWorkouts.enumerated()), id: \.element.id) { index, workout in
                    if index > 0 {
                        Divider().overlay(Color.fbDivider)
                    }
                    WorkoutSessionRow(workout: workout)
                }
                if remainingCount > 0 {
                    Divider().overlay(Color.fbDivider)
                    Text("+ \(remainingCount) more in the last 90 days")
                        .font(.caption)
                        .foregroundStyle(Color.fbMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
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

    private var visibleWorkouts: [WorkoutSummary] {
        Array(workouts.prefix(limit))
    }

    private var remainingCount: Int {
        max(workouts.count - limit, 0)
    }
}

#Preview {
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
        },
        limit: 5
    )
    .padding()
    .background(Color.fbBackground)
}
