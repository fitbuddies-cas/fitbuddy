import SwiftUI

/// The dashboard as it looks with data: the window's headline figures, the
/// muscle-group distribution and the recent sessions (US-2 AC1).
///
/// Split from `DashboardView` so the loaded layout can be previewed and
/// rendered on its own, without driving a ViewModel through its states.
struct DashboardContentView: View {
    let workouts: [WorkoutSummary]
    let metrics: DashboardMetrics

    var body: some View {
        VStack(spacing: 12) {
            windowLabel
            FBCard(padding: 18) {
                FBStat(
                    label: "Total volume",
                    value: VolumeFormatter.full(metrics.totalVolumeKg),
                    unit: "kg"
                )
            }
            HStack(spacing: 12) {
                FBCard {
                    FBStat(
                        label: "Avg / week",
                        value: metrics.averageTrainingDaysPerWeek.formatted(.number.precision(.fractionLength(1))),
                        unit: "days"
                    )
                }
                FBCard {
                    FBStat(label: "Sessions", value: "\(metrics.workoutCount)", unit: "total")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            MuscleDistributionCard(distribution: metrics.muscleDistribution)
            RecentSessionsCard(workouts: workouts)
        }
    }

    private var windowLabel: some View {
        Text("Last 90 days".uppercased())
            .font(.fbLabel)
            .tracking(0.6)
            .foregroundStyle(Color.fbMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview {
    ScrollView {
        DashboardContentView(
            workouts: PreviewWorkoutCache.filled.summaries,
            metrics: DashboardMetrics(summaries: PreviewWorkoutCache.filled.summaries)
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}
#endif
