import SwiftUI

/// The two buttons under a finished recommendation (US-3 AC9, #32).
///
/// A tap is stored on the device and nothing else happens — no request, no
/// backend. Once a verdict is in, the bar makes room for the cooldown label,
/// which is what the user actually needs next.
struct AnalysisFeedbackBar: View {
    /// The verdict already given for this recommendation, if any.
    let selected: AnalysisFeedback?
    /// `"Next analysis available in 5h 12m"`, or `nil` while a run is allowed.
    let cooldownMessage: String?
    let onSelect: (AnalysisFeedback) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let selected {
                Text(thanks(for: selected))
                    .font(.footnote)
                    .foregroundStyle(Color.fbMuted)
                if let cooldownMessage {
                    Text(cooldownMessage)
                        .font(.subheadline.weight(.semibold))
                        .fbTabularNumbers()
                        .foregroundStyle(Color.fbInk)
                }
            } else {
                Text("Was this helpful?")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.fbInkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach(AnalysisFeedback.allCases, id: \.self) { verdict in
                        button(for: verdict)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.bar)
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    private func button(for verdict: AnalysisFeedback) -> some View {
        Button {
            onSelect(verdict)
        } label: {
            Label(verdict.label, systemImage: verdict.symbolName)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.fb(verdict == .helpful ? .accent : .secondary))
        .frame(height: 44)
    }

    /// Different wording per verdict on purpose: thanking someone for "Not
    /// helpful" with the same line reads as if the tap was not registered.
    private func thanks(for verdict: AnalysisFeedback) -> String {
        switch verdict {
        case .helpful:
            return "Thanks for the feedback."
        case .notHelpful:
            return "Thanks — noted for the next analysis."
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
#endif
