import SwiftUI

/// The resting state of the analysis screen: what the analysis is, what it
/// sends, and the button that starts it (#32).
struct AnalysisIntroView: View {
    /// `false` only while a run is in flight — the intro is not on screen
    /// then, but the button must not be tappable twice in the same frame.
    let canStart: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FBCard(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    // No provider name here: which one answers is only
                    // decided once the run starts and the chain resolves, so
                    // naming one now could turn out to be wrong (#79).
                    Text("AI".uppercased())
                        .font(.fbLabel)
                        .tracking(0.6)
                        .foregroundStyle(Color.fbMuted)
                    Text("Ready for a progression check?")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.fbInk)
                    Text("""
                    Your AI provider reads the last 4 weeks of your cached training \
                    data and compares them with the 4 weeks before, then names one \
                    concrete next step.
                    """)
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInkSecondary)
                }
            }

            Button("Analyze with AI", action: onStart)
                .buttonStyle(.fb(.accent))
                .disabled(!canStart)

            AnalysisPrivacyNote()
        }
    }
}

#if DEBUG
#Preview("Ready") {
    AnalysisIntroView(canStart: true, onStart: {})
        .padding(16)
        .background(Color.fbBackground)
}
#endif
