import SwiftUI

/// The dashboard's entry point into the AI analysis (US-3, #32).
///
/// Deliberately the loudest element on the dashboard: the recommendation is
/// the product, and everything above it is the data it is built from.
struct AnalysisCTACard: View {
    let onAnalyze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Provider-neutral: which provider answers is the user's priority
            // order plus whatever the fallback chain reaches (#79), and it is
            // only known once the run starts. The answering provider is named
            // on the result itself; naming one here made the dashboard claim
            // Claude to users who had configured Gemini or Mistral.
            Text("AI Analysis".uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbBackground.opacity(0.6))
            Text("Ready for a progression check?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.fbBackground)
            Text("Based on your last 4 weeks, get one concrete recommendation.")
                .font(.subheadline)
                .foregroundStyle(Color.fbBackground.opacity(0.7))
                .padding(.bottom, 8)
            Button("Analyze with AI", action: onAnalyze)
                .buttonStyle(.fb(.accent, fullWidth: false))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        // `fbInk` is the inverse surface in both appearances, so the card stays
        // the darkest thing on a light dashboard and the lightest on a dark one.
        .background(Color.fbInk)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.card))
    }
}

#if DEBUG
#Preview {
    AnalysisCTACard(onAnalyze: {})
        .padding(16)
        .background(Color.fbBackground)
}
#endif
