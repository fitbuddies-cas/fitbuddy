import SwiftUI

/// The resting state of the analysis screen: what the analysis is, what it
/// sends, and the button that starts it (#32).
struct AnalysisIntroView: View {
    /// `"Next analysis available in 5h 12m"`, or `nil` while a run is allowed.
    let cooldownMessage: String?
    let canStart: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FBCard(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI · Claude".uppercased())
                        .font(.fbLabel)
                        .tracking(0.6)
                        .foregroundStyle(Color.fbMuted)
                    Text("Ready for a progression check?")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.fbInk)
                    Text("""
                    Claude reads the last 4 weeks of your cached training data and \
                    compares them with the 4 weeks before, then names one concrete \
                    next step.
                    """)
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInkSecondary)
                }
            }

            Button("Analyze with AI", action: onStart)
                .buttonStyle(.fb(.accent))
                .disabled(!canStart)

            if let cooldownMessage {
                Text(cooldownMessage)
                    .font(.footnote)
                    .fbTabularNumbers()
                    .foregroundStyle(Color.fbMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            privacyNote
        }
    }

    /// The one claim the user cannot verify from the screen itself, so it is
    /// stated where the tap happens rather than only in the consent text
    /// (US-3 AC3).
    private var privacyNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.caption2)
            Text("Only your own training data is sent to Claude — no benchmarks.")
                .font(.caption)
        }
        .foregroundStyle(Color.fbMuted)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }
}

#if DEBUG
#Preview("Ready") {
    AnalysisIntroView(cooldownMessage: nil, canStart: true, onStart: {})
        .padding(16)
        .background(Color.fbBackground)
}

#Preview("On cooldown") {
    AnalysisIntroView(
        cooldownMessage: "Next analysis available in 5h 12m",
        canStart: false,
        onStart: {}
    )
    .padding(16)
    .background(Color.fbBackground)
}
#endif
