import SwiftUI

/// The finished recommendation, plus the disclaimer that has to sit with it
/// (#32).
///
/// Every provider answers in prose under 200 words (see
/// `AnalysisPromptBuilder`), so
/// the text is rendered as it comes rather than parsed into cards: a layout
/// that promises structured fields would misrepresent what the model was asked
/// for.
struct AnalysisResultView: View {
    let text: String
    /// Who answered, and who was asked before them (#79). `nil` only in the
    /// degenerate case of a result with no recorded attempt.
    let attribution: AnalysisAttribution?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(badge.uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            if let notice = attribution?.fallbackNotice {
                fallbackNotice(notice)
            }
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

    /// Names the model that actually wrote this, not the one the user ranked
    /// first — after a fallback those are different, and attributing the text
    /// to the wrong provider would be a lie about where their data went.
    private var badge: String {
        guard let attribution else { return "AI" }
        return "AI · \(attribution.provider.displayName)"
    }

    /// Shown only after a fallback: the answer is fine, but the user asked for
    /// a different model and is owed the reason they did not get it.
    private func fallbackNotice(_ notice: String) -> some View {
        FBInfoRow(
            icon: "arrow.triangle.branch",
            title: "Switched provider",
            text: notice
        )
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
/// The four-week recommendation used by both previews.
private let previewRecommendation = """
    Across the last four weeks you trained 14 times, with chest and back \
    carrying most of the volume while legs appeared in only 3 sessions.

    Bench press has sat at 60 kg for five sessions at the same rep count — \
    that is a clean overload signal. Add 2.5 kg on your next session and \
    keep the reps where they are. Give legs a second slot in the week \
    before you push upper-body volume any further.
    """

#Preview("Answered first try") {
    ScrollView {
        AnalysisResultView(
            text: previewRecommendation,
            attribution: AnalysisAttribution(first: .claude)
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}

#Preview("After a fallback") {
    ScrollView {
        AnalysisResultView(
            text: previewRecommendation,
            attribution: {
                var attribution = AnalysisAttribution(first: .claude)
                attribution.append(.gemini)
                return attribution
            }()
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}
#endif
