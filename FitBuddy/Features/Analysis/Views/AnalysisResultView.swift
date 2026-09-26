import SwiftUI

/// The finished recommendation, plus the disclaimer that has to sit with it
/// (#32).
///
/// A validated report renders as design 3.4/3.4b/3.5 draws it (US-14 AC1,
/// #177, #170): the verdict headline, the context line (US-6), the lead, zero
/// to four cards, the full analysis behind "Show full analysis", the
/// disclaimer. The disclosure starts open when no card is actionable
/// (`AnalysisFullAnalysis`), so thin data still shows its whole answer.
///
/// A prose answer — a provider without JSON output, a non-conforming answer
/// (US-14 AC5), a row stored before V4 (AC6) — keeps the look it had before
/// the cards: the model's own outline, parsed into heading, paragraph and
/// bullet (#117), in one card under the context line.
struct AnalysisResultView: View {
    let outcome: AnalysisOutcome
    /// What the recommendation rests on (US-6). `nil` only where no run
    /// context exists, e.g. a preview.
    let context: AnalysisContext?
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
    /// Whether to show the one-time effort hint (#245, US-18 AC6). Decided by
    /// `AnalysisViewModel`; `false` everywhere else, the history included.
    var showsEffortHint = false
    /// Starts over from the intro screen. `nil` where no new run belongs, e.g.
    /// the history detail.
    var onNewAnalysis: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let notice = attribution?.fallbackNotice {
                fallbackNotice(notice)
            }
            switch outcome {
            case .report(let report):
                reportBody(report)
            case .prose(let text):
                proseBody(text)
            }
            if showsEffortHint {
                effortHint
            }
            disclaimer
            if let onNewAnalysis {
                Button("New analysis", action: onNewAnalysis)
                    .buttonStyle(FBButtonStyle(kind: .secondary))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Analysis.result)
    }

    /// Headline, context line, lead, cards, full analysis — in the order of
    /// US-14 AC1. The context sits under the verdict rather than above the
    /// whole result, as in design 3.4: the verdict is what the user came for,
    /// the basis is what they read it against.
    private func reportBody(_ report: ValidatedAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                AnalysisHeadlineView(verdict: report.verdict)
                if let context {
                    AnalysisContextView(context: context)
                }
                if report.hasLead {
                    Text(report.lead)
                        .font(.body)
                        .foregroundStyle(Color.fbInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                        .accessibilityIdentifier(AccessibilityID.Analysis.lead)
                }
            }
            if !report.cards.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(report.cards.enumerated()), id: \.offset) { item in
                        AnalysisReportCardView(card: item.element)
                    }
                }
            }
            if report.hasFullAnalysis {
                AnalysisFullAnalysisView(
                    summary: report.summary,
                    startsExpanded: AnalysisFullAnalysis.startsExpanded(for: report.cards)
                )
                // A different report starts from its own rule, not from the
                // state the previous one was left in.
                .id(report.summary)
            }
        }
    }

    private func proseBody(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let context {
                AnalysisContextView(context: context)
            }
            FBCard(padding: 18) {
                AnalysisFormattedText(text: text)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.Analysis.prose)
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

    /// The one-time hint of US-18 AC6: one line, no dialog, no question about
    /// past sessions. Drawn as the design's soft hint strip (the dashboard's
    /// imbalance hint in `design/fb-screens.jsx`), in the accent tone rather
    /// than the warning one — nothing is wrong with the analysis above it.
    private var effortHint: some View {
        HStack(alignment: .center, spacing: 6) {
            Circle()
                .fill(Color.fbAccent)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text("Analyses get more precise when your sessions carry an effort value, like RPE in Hevy.")
                .font(.caption)
                .foregroundStyle(Color.fbInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fbAccentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Analysis.effortHint)
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
/// The four-week prose recommendation of the fallback preview.
private let previewRecommendation = """
    Across the last four weeks you trained 14 times, with chest and back \
    carrying most of the volume while legs appeared in only 3 sessions.

    **Progressive overload**
    Bench press has sat at 60 kg for five sessions at the same rep count — \
    that is a clean overload signal.

    - Add 2.5 kg on your next session and keep the reps where they are
    - Give legs a second slot before you push upper-body volume further
    """

private let previewContext = AnalysisContext(sessionCount: 14, window: .default)

/// Design 3.4.
#Preview("Report · progress") {
    ScrollView {
        AnalysisResultView(
            outcome: .report(AnalysisReportSamples.progress),
            context: previewContext,
            attribution: AnalysisAttribution(first: .claude),
            age: "just now"
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}

/// Design 3.5.
#Preview("Report · recover") {
    ScrollView {
        AnalysisResultView(
            outcome: .report(AnalysisReportSamples.recover),
            context: previewContext,
            attribution: AnalysisAttribution(first: .claude),
            age: "just now"
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}

/// Design 3.4b: thin data, no cards, the full analysis open.
#Preview("Report · thin data") {
    ScrollView {
        AnalysisResultView(
            outcome: .report(AnalysisReportSamples.thin),
            context: AnalysisContext(sessionCount: 2, window: .default),
            attribution: AnalysisAttribution(first: .mistral),
            age: "1 h ago"
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}

/// #227 / ADR-014 §6: the app found no verdict, says so, and shows the one
/// note naming why. No progression and no recovery card sit under it.
#Preview("Report · no verdict") {
    ScrollView {
        AnalysisResultView(
            outcome: .report(AnalysisReportSamples.insufficientData),
            context: AnalysisContext(sessionCount: 3, window: .default),
            attribution: AnalysisAttribution(first: .claude),
            age: "just now"
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}

/// US-14 AC5: the answer was not a report, and looks as it did before #177.
#Preview("Prose fallback") {
    ScrollView {
        AnalysisResultView(
            outcome: .prose(previewRecommendation),
            context: previewContext,
            attribution: AnalysisAttribution(first: .claude),
            age: "just now"
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}

/// #245 / US-18 AC6: no effort value anywhere in the window, first time.
#Preview("Effort hint") {
    ScrollView {
        AnalysisResultView(
            outcome: .report(AnalysisReportSamples.progress),
            context: previewContext,
            attribution: AnalysisAttribution(first: .claude),
            age: "just now",
            showsEffortHint: true
        )
        .padding(16)
    }
    .background(Color.fbBackground)
}

/// A recommendation brought back from disk after an app restart (#97): the
/// provider and the age are stored (#176), the fallback chain is not, and the
/// way back to the intro screen is offered.
#Preview("Restored") {
    ScrollView {
        AnalysisResultView(
            outcome: .report(AnalysisReportSamples.progress),
            context: previewContext,
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
            outcome: .report(AnalysisReportSamples.progress),
            context: previewContext,
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
