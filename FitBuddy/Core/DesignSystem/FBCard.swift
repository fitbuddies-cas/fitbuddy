import SwiftUI

/// White rounded container with a hairline border, matching the `FBCard`
/// primitive from `design/fb-atoms.jsx`.
///
/// `background` and `border` exist for the tinted variant the design draws on
/// the recovery card (`fb-screens.jsx`, `RecoveryRecCard`): same shape and
/// padding, warn-soft fill. Every other card keeps the defaults.
struct FBCard<Content: View>: View {
    var padding: CGFloat = 16
    var background: Color = .fbCard
    var border: Color = .fbBorder
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: FBRadius.card)
                    .strokeBorder(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: FBRadius.card))
    }
}
