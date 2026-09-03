import SwiftUI

/// Onboarding progress bar shared by the step screens: one capsule segment per
/// step, filled up to the current step, with a trailing "Step X of Y" label.
struct FBStepIndicator: View {
    /// 1-based step this screen represents.
    let current: Int
    var total: Int = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < current ? Color.fbInk : Color.fbBorder)
                    .frame(height: 3)
            }
            Text("Step \(current) of \(total)")
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
                .padding(.leading, 8)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Onboarding step \(current) of \(total)")
    }
}
