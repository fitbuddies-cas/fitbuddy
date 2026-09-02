import SwiftUI

/// A single labelled progress bar with a trailing value, matching the `FBBar`
/// primitive from `design/fb-atoms.jsx`.
///
/// Used by `ExerciseDetailCard` (#98) for an exercise's share of its session's
/// volume. Deliberately not the dashboard's muscle-group distribution (#27),
/// which is a Swift Charts bar chart as that task requires — this is the plain
/// share bar for the places that need one outside a chart.
struct FBBar: View {
    let label: String
    /// Fill fraction in the range `0...1`.
    let fraction: Double
    var color: Color = .fbAccent
    var value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.fbInkSecondary)
                .frame(width: 64, alignment: .leading)

            GeometryReader { geo in
                Capsule()
                    .fill(Color.fbCardSubtle)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * clampedFraction)
                    }
            }
            .frame(height: 8)

            Text(value)
                .font(.system(size: 12))
                .fbTabularNumbers()
                .foregroundStyle(Color.fbMuted)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }

    private var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }
}
