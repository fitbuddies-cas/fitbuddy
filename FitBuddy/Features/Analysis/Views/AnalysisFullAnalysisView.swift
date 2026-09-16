import SwiftUI

/// The report's `summary` behind a "Show full analysis" toggle, below the
/// cards (US-14 AC1, #170).
///
/// Whether it starts open is `AnalysisFullAnalysis.startsExpanded(for:)`'s
/// call; after that, the state is the user's and lives only as long as the
/// view.
struct AnalysisFullAnalysisView: View {
    let summary: String
    @State private var isExpanded: Bool

    init(summary: String, startsExpanded: Bool) {
        self.summary = summary
        _isExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        FBCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                toggle
                if isExpanded {
                    Divider().overlay(Color.fbDivider)
                    AnalysisFormattedText(text: summary)
                        .textSelection(.enabled)
                        .padding(16)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(AccessibilityID.Analysis.fullAnalysis)
                }
            }
        }
    }

    private var toggle: some View {
        let title = AnalysisFullAnalysis.toggleTitle(isExpanded: isExpanded)
        return Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.fbInk)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.fbMuted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // VoiceOver reads one stable name plus the state, the way a system
        // disclosure does; Voice Control still answers to the visible title.
        .accessibilityLabel("Full analysis")
        .accessibilityValue(AnalysisFullAnalysis.accessibilityValue(isExpanded: isExpanded))
        .accessibilityInputLabels([Text(title), Text("Full analysis")])
        .accessibilityIdentifier(AccessibilityID.Analysis.fullAnalysisToggle)
    }
}

#if DEBUG
#Preview("Collapsed") {
    AnalysisFullAnalysisView(summary: AnalysisReportSamples.progress.summary, startsExpanded: false)
        .padding(16)
        .background(Color.fbBackground)
}

#Preview("Expanded") {
    AnalysisFullAnalysisView(summary: AnalysisReportSamples.thin.summary, startsExpanded: true)
        .padding(16)
        .background(Color.fbBackground)
}
#endif
