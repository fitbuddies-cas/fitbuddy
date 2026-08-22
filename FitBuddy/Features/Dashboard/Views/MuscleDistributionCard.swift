import Charts
import SwiftUI

/// Muscle-group distribution of the window's training volume (US-2 AC1) as a
/// horizontal bar chart.
///
/// The chart is a single kg scale and only carries groups that produced kg
/// volume. Groups trained without weight — pull-ups, planks, cardio — are
/// listed underneath with their set count instead of being drawn: on a kg
/// scale their bar is zero pixels long, which is indistinguishable from not
/// having trained the group at all. A second encoding inside the same bars
/// would be worse: it would let sets and kilograms share one axis.
struct MuscleDistributionCard: View {
    let distribution: [MuscleLoad]

    var body: some View {
        FBCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if weighted.isEmpty {
                    Text("No weighted sets in this window.")
                        .font(.subheadline)
                        .foregroundStyle(Color.fbMuted)
                } else {
                    chart
                }
                if !setsOnly.isEmpty {
                    bodyweightNote
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Muscle distribution".uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            Spacer()
            Text("kg volume")
                .font(.caption2)
                .foregroundStyle(Color.fbMuted)
        }
    }

    private var chart: some View {
        Chart(weighted) { load in
            BarMark(
                x: .value("Volume", load.volumeKg),
                y: .value("Muscle group", load.group.displayName)
            )
            .foregroundStyle(Color.fbAccent)
            .cornerRadius(4)
            .annotation(position: .trailing, alignment: .leading) {
                Text(VolumeFormatter.compact(load.volumeKg))
                    .font(.caption2)
                    .fbTabularNumbers()
                    .foregroundStyle(Color.fbMuted)
            }
            .accessibilityLabel(load.group.displayName)
            .accessibilityValue("\(VolumeFormatter.full(load.volumeKg)) kilograms, \(load.setCount) sets")
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading) { _ in
                AxisValueLabel()
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.fbInkSecondary)
            }
        }
        .chartXAxis(.hidden)
        // Category order comes from the data (heaviest first); leaving it to
        // Charts would sort the groups alphabetically.
        .chartYScale(domain: weighted.map(\.group.displayName))
        // Room for the trailing annotation, which is drawn outside the plot.
        .chartXScale(domain: 0...maxVolume * 1.25)
        .frame(height: CGFloat(weighted.count) * 30 + 10)
    }

    /// Groups the user trained without weight. Named rather than charted, so
    /// the card does not imply they were skipped.
    private var bodyweightNote: some View {
        Text("Bodyweight & cardio: \(setsOnly.map { "\($0.group.displayName) \($0.setCount) sets" }.joined(separator: " · "))")
            .font(.caption2)
            .foregroundStyle(Color.fbMuted)
            .padding(.top, 2)
    }

    private var weighted: [MuscleLoad] {
        distribution.filter { $0.volumeKg > 0 }
    }

    private var setsOnly: [MuscleLoad] {
        distribution.filter { $0.volumeKg <= 0 }
    }

    /// Never zero, so the x scale stays valid.
    private var maxVolume: Double {
        max(weighted.map(\.volumeKg).max() ?? 0, 1)
    }
}

#if DEBUG
#Preview {
    MuscleDistributionCard(distribution: [
        MuscleLoad(group: .chest, volumeKg: 46_200, setCount: 84),
        MuscleLoad(group: .back, volumeKg: 40_100, setCount: 92),
        MuscleLoad(group: .legs, volumeKg: 22_400, setCount: 61),
        MuscleLoad(group: .shoulders, volumeKg: 12_800, setCount: 48),
        MuscleLoad(group: .arms, volumeKg: 8_400, setCount: 55),
        MuscleLoad(group: .core, volumeKg: 0, setCount: 24),
    ])
    .padding()
    .background(Color.fbBackground)
}
#endif
