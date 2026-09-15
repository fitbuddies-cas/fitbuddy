import Charts
import SwiftUI

/// The estimated-1RM curve of one movement over the cached window
/// (US-9 AC1, #42).
///
/// A line with a point per session, not a bar chart: the sessions are spaced
/// by whatever the user's week looked like, and bars of equal width would
/// claim an even rhythm the training did not have. The x-axis is the real
/// date, so a three-week gap looks like a three-week gap.
///
/// The y-axis deliberately does not start at zero. Nobody's bench goes to
/// nothing, and a scale from zero flattens the ten kilos a mesocycle is
/// actually about into a line that looks flat — the chart would hide exactly
/// what it exists to show. The padded domain below keeps the change readable
/// while the axis labels say what the numbers are.
struct ProgressionChartCard: View {
    let points: [ProgressionPoint]

    var body: some View {
        FBCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                header
                chart
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Estimated 1RM".uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            Spacer()
            Text("kg · Epley")
                .font(.caption2)
                .foregroundStyle(Color.fbMuted)
        }
    }

    private var chart: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.sessionStart),
                y: .value("Estimated 1RM", point.estimatedOneRepMaxKg)
            )
            .foregroundStyle(Color.fbAccent)
            .interpolationMethod(.monotone)
            PointMark(
                x: .value("Date", point.sessionStart),
                y: .value("Estimated 1RM", point.estimatedOneRepMaxKg)
            )
            .foregroundStyle(Color.fbAccent)
            .symbolSize(36)
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.fbDivider)
                AxisValueLabel {
                    if let kilograms = value.as(Double.self) {
                        Text(OneRepMaxFormatter.kilograms(kilograms))
                            .font(.caption2)
                            .fbTabularNumbers()
                            .foregroundStyle(Color.fbMuted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.fbDivider)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.day().month(.abbreviated))
                            .font(.caption2)
                            .foregroundStyle(Color.fbMuted)
                    }
                }
            }
        }
        .frame(height: 180)
        // The marks carry no labels a screen reader could read out, so the
        // chart describes itself as one element instead of announcing an empty
        // graphic.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(AccessibilityID.Progression.chart)
    }

    /// Padded by a tenth of the span on each side, with a floor of 2.5 kg so a
    /// flat series still gets a band rather than a line pinned to the frame.
    ///
    /// The lower bound stops at zero. On a light movement the 2.5 kg floor is
    /// larger than the values themselves — a 1.25 kg set for 8 estimates at
    /// ~1.6 kg — and the axis would label negative kilograms, a number that
    /// does not exist here. Clamping costs nothing at normal loads, where the
    /// padding never reaches zero anyway.
    private var domain: ClosedRange<Double> {
        let values = points.map(\.estimatedOneRepMaxKg)
        guard let lowest = values.min(), let highest = values.max() else { return 0...1 }
        let padding = max((highest - lowest) * 0.1, 2.5)
        return max(lowest - padding, 0)...(highest + padding)
    }

    private var accessibilityLabel: String {
        guard let first = points.first, let last = points.last else {
            return "Estimated one-rep-max chart"
        }
        return """
        Estimated one-rep-max over \(points.count) sessions, \
        from \(OneRepMaxFormatter.kilograms(first.estimatedOneRepMaxKg)) kilograms \
        to \(OneRepMaxFormatter.kilograms(last.estimatedOneRepMaxKg)) kilograms.
        """
    }
}

#if DEBUG
#Preview("Progression chart") {
    ProgressionChartCard(points: PreviewProgressionCache.risingPoints)
        .padding(16)
        .background(Color.fbBackground)
}
#endif
