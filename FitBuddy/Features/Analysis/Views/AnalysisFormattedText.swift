import SwiftUI

/// Renders an AI recommendation the way the model structured it (#117).
///
/// One view for all three places a recommendation appears — the finished
/// result, the answer as it streams in, and the previews behind them — so a
/// heading never renders as a title in one and as asterisks in another.
///
/// Presentational only: `AnalysisTextFormatter` decides what the blocks are,
/// this decides what they look like.
struct AnalysisFormattedText: View {
    let text: String

    /// Rebuilt on each body pass rather than cached: while streaming, `text`
    /// changes with every chunk anyway, and the formatter is a pure pass over
    /// a few hundred words.
    private var blocks: [AnalysisTextBlock] {
        AnalysisTextFormatter.blocks(from: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { item in
                view(for: item.element)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: AnalysisTextBlock) -> some View {
        switch block {
        case .heading(let title):
            Text(title)
                .font(.fbTitle)
                .foregroundStyle(Color.fbInk)
                // Extra room above, none below: a heading belongs to what
                // follows it, and the same gap on both sides would leave it
                // floating between two paragraphs.
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(Color.fbInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let item):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Drawn here rather than kept from the raw text, so "-", "*"
                // and "1." all come out as the same list.
                Text("•")
                    .font(.body)
                    .foregroundStyle(Color.fbMuted)
                Text(item)
                    .font(.body)
                    .foregroundStyle(Color.fbInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        FBCard(padding: 18) {
            AnalysisFormattedText(text: """
            You trained 14 times in the last four weeks, with chest and back \
            carrying most of the volume.

            **Progressive overload**
            Bench press has sat at 60 kg for five sessions:

            - Add 2.5 kg on your next session and keep the reps
            - Give legs a second slot before adding upper-body volume

            Everything else can stay as it is *for now*.
            """)
        }
        .padding(16)
    }
    .background(Color.fbBackground)
}
#endif
