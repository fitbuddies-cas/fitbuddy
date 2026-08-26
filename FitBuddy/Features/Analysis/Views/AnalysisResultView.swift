import SwiftUI

/// The finished recommendation, plus the disclaimer that has to sit with it
/// (#32).
///
/// Claude answers in prose under 200 words (see `AnalysisPromptBuilder`), so
/// the text is rendered as it comes rather than parsed into cards: a layout
/// that promises structured fields would misrepresent what the model was asked
/// for.
struct AnalysisResultView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI · Claude".uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            FBCard(padding: 18) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(Color.fbInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            disclaimer
        }
    }

    /// FitBuddy is not a medical product, and the recommendation is the one
    /// place in the app where a user could mistake it for one.
    private var disclaimer: some View {
        Text("""
        FitBuddy is not a medical product. You are responsible for any training \
        change you make.
        """)
        .font(.caption)
        .foregroundStyle(Color.fbMuted)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.fbBorder)
                .frame(width: 2)
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        AnalysisResultView(text: """
        Across the last four weeks you trained 14 times, with chest and back \
        carrying most of the volume while legs appeared in only 3 sessions.

        Bench press has sat at 60 kg for five sessions at the same rep count — \
        that is a clean overload signal. Add 2.5 kg on your next session and \
        keep the reps where they are. Give legs a second slot in the week \
        before you push upper-body volume any further.
        """)
        .padding(16)
    }
    .background(Color.fbBackground)
}
#endif
