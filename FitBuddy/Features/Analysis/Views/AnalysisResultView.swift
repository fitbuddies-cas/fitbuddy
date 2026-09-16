import SwiftUI

/// The finished recommendation, plus the disclaimer that has to sit with it
/// (#32).
///
/// Every provider answers in prose under 200 words (see
/// `AnalysisPromptBuilder`), and structures that prose with Markdown even
/// though nothing asked it to. So what is parsed here is the model's own
/// outline — heading, paragraph, bullet — and nothing beyond it (#117): a card
/// raster with fields we invented would misrepresent what the model was asked
/// for, and rendering the markers verbatim made the paid-for answer the least
/// readable text on screen.
struct AnalysisResultView: View {
    let text: String
    /// Who answered, and who was asked before them (#79). A recommendation
    /// restored from disk carries only the provider that answered (#176), so
    /// it never shows the fallback notice. `nil` in the degenerate case of a
    /// result with no recorded attempt, and on a row stored before #176.
    let attribution: AnalysisAttribution?
    /// How old the recommendation is (`"2 h ago"`), or `nil` while it has no
    /// timestamp. Always set for a restored one, where the age is the whole
    /// point: the user has to know they are looking at yesterday's advice
    /// (US-3 AC10, #97).
    var age: String? = nil
    /// Starts over from the intro screen. `nil` while the lock blocks a
    /// new run — an enabled button that cannot do anything is worse than no
    /// button, and the lock label in the footer already explains the wait.
    var onNewAnalysis: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let notice = attribution?.fallbackNotice {
                fallbackNotice(notice)
            }
            FBCard(padding: 18) {
                AnalysisFormattedText(text: text)
                    .textSelection(.enabled)
            }
            disclaimer
            if let onNewAnalysis {
                Button("New analysis", action: onNewAnalysis)
                    .buttonStyle(FBButtonStyle(kind: .secondary))
            }
        }
    }

    /// When it was written on the left, who wrote it on the right.
    ///
    /// Split apart from the badge it used to share (#117): with a history, the
    /// age is what tells one recommendation from another, and "AI · CLAUDE ·
    /// 2 h ago" buried it at the end of a string most readers stop reading
    /// after the provider's name.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let age {
                Text(age)
                    .font(.fbLabel)
                    .foregroundStyle(Color.fbInkSecondary)
            }
            Spacer(minLength: 8)
            Text(badge.uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
        }
    }

    /// Names the model that actually wrote this, not the one the user ranked
    /// first — after a fallback those are different, and attributing the text
    /// to the wrong provider would be a lie about where their data went.
    ///
    /// `"AI · CLAUDE"` — live or restored from disk (#176) — or a bare
    /// `"AI"` on a row stored before the provider was recorded.
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

    **Progressive overload**
    Bench press has sat at 60 kg for five sessions at the same rep count — \
    that is a clean overload signal.

    - Add 2.5 kg on your next session and keep the reps where they are
    - Give legs a second slot before you push upper-body volume further
    """

#Preview("Answered first try") {
    ScrollView {
        AnalysisResultView(
            text: previewRecommendation,
            attribution: AnalysisAttribution(first: .claude),
            age: "just now"
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}

/// A recommendation brought back from disk after an app restart (#97): the
/// provider and the age are stored (#176), the fallback chain is not, and the
/// lock has since expired — so the way back to the intro screen is offered.
#Preview("Restored") {
    ScrollView {
        AnalysisResultView(
            text: previewRecommendation,
            attribution: AnalysisAttribution(first: .gemini),
            age: "7 h ago",
            onNewAnalysis: {}
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
