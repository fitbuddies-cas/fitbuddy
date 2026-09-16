import SwiftUI

/// One selectable answer on the training profile screen (US-13, step 4).
///
/// Its own type for the reason `ExerciseSummaryRow` and `SetDetailRow` are:
/// both questions render the same row, and a row that exists once can be
/// looked at on its own — a `ScrollView`'s contents cannot.
///
/// Tapping the selected row clears it. Without that a mis-tap is permanent for
/// the rest of the step: there is no "none of these" option, and the way out
/// would be to skip the whole screen.
struct TrainingProfileOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.fbAccent : Color.fbTertiary)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
#Preview("Options") {
    FBCard(padding: 0) {
        VStack(spacing: 0) {
            TrainingProfileOptionRow(title: "Build muscle", isSelected: true) {}
            TrainingProfileOptionRow(title: "Improve endurance", isSelected: false) {}
        }
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
