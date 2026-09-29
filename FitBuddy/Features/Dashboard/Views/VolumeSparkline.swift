import Charts
import SwiftUI

/// The 13-week volume trend under the dashboard's hero stat (design 2.1): a
/// thin accent line over a fill that fades out downwards, no axes and no
/// labels. The figure above it carries the number; the line only says which
/// way it has been moving.
struct VolumeSparkline: View {
    /// One value per week, oldest first — `DashboardMetrics.weeklyVolumesKg`.
    let weeklyVolumesKg: [Double]

    private struct WeekPoint: Identifiable {
        let id: Int
        let volumeKg: Double
    }

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Week", point.id), y: .value("Volume", point.volumeKg))
                .interpolationMethod(.monotone)
                .foregroundStyle(fill)
            LineMark(x: .value("Week", point.id), y: .value("Volume", point.volumeKg))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.fbAccent)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        // Headroom for the stroke: at exactly the maximum the 2 pt line would
        // be shaved by the plot edge.
        .chartYScale(domain: 0...(maxVolume * 1.08))
        .chartXScale(domain: 0...Double(max(points.count - 1, 1)))
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Weekly volume trend")
        .accessibilityValue(accessibilityValue)
    }

    private var points: [WeekPoint] {
        weeklyVolumesKg.enumerated().map { WeekPoint(id: $0.offset, volumeKg: $0.element) }
    }

    private var fill: LinearGradient {
        LinearGradient(
            colors: [Color.fbAccent.opacity(0.25), Color.fbAccent.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// At least 1 so an all-zero window still yields a valid scale.
    private var maxVolume: Double {
        max(weeklyVolumesKg.max() ?? 0, 1)
    }

    private var accessibilityValue: String {
        guard let first = weeklyVolumesKg.first, let last = weeklyVolumesKg.last else {
            return "No data"
        }
        return "From \(VolumeFormatter.full(first)) kilograms in the first week to \(VolumeFormatter.full(last)) kilograms in the latest week"
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        FBCard(padding: 18) {
            VolumeSparkline(weeklyVolumesKg: [4_200, 5_100, 4_800, 6_300, 5_900, 7_100, 6_800, 8_200, 7_600, 8_900, 9_400, 8_700, 10_100])
        }
        FBCard(padding: 18) {
            VolumeSparkline(weeklyVolumesKg: Array(repeating: 0, count: 13))
        }
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
