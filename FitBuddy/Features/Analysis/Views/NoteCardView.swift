import SwiftUI

/// A card without figures: a model note, or a card the validator could not
/// confirm against the cache, reduced to its text (#175, #177).
struct NoteCardView: View {
    let title: String
    let text: String

    var body: some View {
        FBCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.fbInk)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AnalysisCardAccessibility.label(for: .note(title: title, text: text)))
        .accessibilityIdentifier(AccessibilityID.Analysis.noteCard)
    }
}

#if DEBUG
#Preview {
    NoteCardView(
        title: "Rows",
        text: "Add a rep on rows before adding weight — the last two sessions stalled at 8."
    )
    .padding(16)
    .background(Color.fbBackground)
}
#endif
