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
                            .frame(width: geo.size.width * Self.clamped(fraction))
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

    /// The fill fraction as a width multiplier, in `0...1`.
    ///
    /// `min`/`max` alone do not clamp a NaN — in Swift `max(.nan, 0)` is
    /// `.nan`, which would reach `geo.size.width * …` and give the capsule an
    /// invalid frame. A fraction that is not a real number has nothing to show,
    /// so it reads as empty. A rule rather than a computed property so it can
    /// be tested without a view.
    static func clamped(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }
}
