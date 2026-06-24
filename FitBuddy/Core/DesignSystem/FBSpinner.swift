import SwiftUI

/// Indeterminate loading spinner matching the `FBSpinner` primitive from
/// `design/fb-atoms.jsx`: a ring with a colored leading arc that rotates.
struct FBSpinner: View {
    var size: CGFloat = 28
    var color: Color = .fbInk

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.85)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: max(2, size / 14), lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                .linear(duration: 0.9).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}
