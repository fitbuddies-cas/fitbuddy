import SwiftUI

/// The two buttons under a finished recommendation (US-3 AC9, #32).
///
/// A tap is stored on the device and nothing else happens — no request, no
/// backend. The buttons stay put after the tap, with the chosen verdict filled:
/// the store is built to take a changed mind, so the UI has to let the user
/// change it. Below them sits the cooldown label, which is what the user
/// actually needs next.
struct AnalysisFeedbackBar: View {
    /// The verdict already given for this recommendation, if any.
    let selected: AnalysisFeedback?
    /// `"Next analysis available in 5h 12m"`, or `nil` while a run is allowed.
    let cooldownMessage: String?
    let onSelect: (AnalysisFeedback) -> Void

    var body: some View {
        VStack(spacing: 8) {
            prompt
            HStack(spacing: 8) {
                ForEach(AnalysisFeedback.allCases, id: \.self) { verdict in
                    button(for: verdict)
                }
            }
            if let cooldownMessage {
                Text(cooldownMessage)
                    .font(.subheadline.weight(.semibold))
                    .fbTabularNumbers()
                    .foregroundStyle(Color.fbInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // No material of its own: the view sits in `AnalysisView`'s bottom
        // `safeAreaBar`, which fades the content underneath and shares the
        // space with the tab bar's glass (#107).
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    /// The question before the tap, the acknowledgement after it — same slot,
    /// so confirming a verdict does not shift the buttons under the finger.
    private var prompt: some View {
        Group {
            if let selected {
                Text(thanks(for: selected))
                    .foregroundStyle(Color.fbMuted)
            } else {
                Text("Was this helpful?")
                    .foregroundStyle(Color.fbInkSecondary)
            }
        }
        .font(.footnote.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func button(for verdict: AnalysisFeedback) -> some View {
        let isSelected = verdict == selected
        return Button {
            onSelect(verdict)
        } label: {
            Label(verdict.label, systemImage: verdict.symbolName(isSelected: isSelected))
                .font(.subheadline.weight(.semibold))
        }
        // Filled only once chosen: a button that starts out filled would read as
        // the recommended answer and skew the one thing this bar measures.
        .buttonStyle(.fb(style(isSelected: isSelected, verdict: verdict), height: 44))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func style(isSelected: Bool, verdict: AnalysisFeedback) -> FBButtonStyle.Kind {
        guard isSelected else { return .secondary }
        return verdict == .helpful ? .accent : .primary
    }

    /// Different wording per verdict on purpose: thanking someone for "Not
    /// helpful" with the same line reads as if the tap was not registered.
    /// Neither line promises an effect — the verdict is stored locally and
    /// reaches no prompt.
    private func thanks(for verdict: AnalysisFeedback) -> String {
        switch verdict {
        case .helpful:
            return "Thanks for the feedback."
        case .notHelpful:
            return "Thanks — noted."
        }
    }
}

#if DEBUG
#Preview("Unrated") {
    AnalysisFeedbackBar(selected: nil, cooldownMessage: nil, onSelect: { _ in })
}

#Preview("Rated") {
    AnalysisFeedbackBar(
        selected: .helpful,
        cooldownMessage: "Next analysis available in 5h 42m",
        onSelect: { _ in }
    )
}

#Preview("Rated not helpful") {
    AnalysisFeedbackBar(
        selected: .notHelpful,
        cooldownMessage: "Next analysis available in 5h 42m",
        onSelect: { _ in }
    )
}
#endif
