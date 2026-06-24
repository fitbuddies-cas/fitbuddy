import SwiftUI

/// White rounded container with a hairline border, matching the `FBCard`
/// primitive from `design/fb-atoms.jsx`.
struct FBCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fbCard)
            .overlay(
                RoundedRectangle(cornerRadius: FBRadius.card)
                    .strokeBorder(Color.fbBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: FBRadius.card))
    }
}
