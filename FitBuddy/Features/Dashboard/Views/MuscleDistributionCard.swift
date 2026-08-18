import Charts
import SwiftUI

/// Muscle-group distribution of the window's training volume (US-2 AC1) as a
/// horizontal bar chart.
///
/// Bars are sized by kg volume, matching the design's "kg volume" label. Groups
/// that produce no kg volume — bodyweight and cardio work — still appear, with
/// their counted sets as the label, so a pull-up-heavy back does not silently
/// vanish from the chart.
struct MuscleDistributionCard: View {
    let distribution: [MuscleLoad]

    var body: some View {
        FBCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if distribution.isEmpty {
                    Text("No sets logged in this window.")
                        .font(.subheadline)
                        .foregroundStyle(Color.fbMuted)
                } else {
                    chart
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
        Chart(distribution) { load in
            BarMark(
                x: .value("Volume", load.volumeKg),
                y: .value("Muscle group", load.group.displayName)
            )
            .foregroundStyle(Color.fbAccent)
            .cornerRadius(4)
            .annotation(position: .trailing, alignment: .leading) {
                Text(label(for: load))
                    .font(.caption2)
                    .fbTabularNumbers()
                    .foregroundStyle(Color.fbMuted)
            }
            .accessibilityLabel(load.group.displayName)
            .accessibilityValue("\(VolumeFormatter.full(load.volumeKg)) kilograms, \(load.setCount) sets")
        }
        // Category order comes from the data (heaviest first); leaving it to
        // Charts would sort the groups alphabetically.
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading) { _ in
                AxisValueLabel()
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.fbInkSecondary)
            }
        }
        .chartXAxis(.hidden)
        // Room for the trailing annotation, which is drawn outside the plot.
        .chartXScale(domain: 0...maxVolume * 1.25)
        .chartYScale(domain: distribution.map(\.group.displayName))
        .frame(height: CGFloat(distribution.count) * 30 + 10)
    }

    /// Groups without kg volume are labelled by their sets — otherwise every
    /// bodyweight and cardio row would read "0".
    private func label(for load: MuscleLoad) -> String {
        load.volumeKg > 0
            ? VolumeFormatter.compact(load.volumeKg)
            : "\(load.setCount) sets"
    }

    /// Never zero, so the x scale stays valid for an all-bodyweight window.
    private var maxVolume: Double {
        max(distribution.map(\.volumeKg).max() ?? 0, 1)
    }
}

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
