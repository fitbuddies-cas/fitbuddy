import SwiftUI

/// The failed run: what went wrong, and the one thing worth doing about it
/// (#32).
///
/// The wording, the symbol and whether a retry is offered all come from
/// `AnalysisFailure` — the view only lays them out.
struct AnalysisErrorView: View {
    let failure: AnalysisFailure
    /// Who was tried before giving up (#79). Named only when there was more
    /// than one: `failure` already describes the last provider's problem, and
    /// on a single-provider run repeating that name adds nothing.
    let attribution: AnalysisAttribution?
    /// `nil` for a failure a retry cannot fix (a missing or rejected key, no
    /// training data), where a "Try again" button would only produce the same
    /// message again.
    let onRetry: (() -> Void)?
    /// Returns to the intro state — the button reads "Back", and that is what
    /// it does; it does not leave the analysis tab.
    let onBack: () -> Void

    /// `"Tried Claude, then Gemini."` — without it, a user who set up three
    /// providers has no way to tell a chain that fell all the way through from
    /// one that never got past the first.
    private var attemptedNotice: String? {
        guard let attribution, attribution.didFallBack else { return nil }
        return "Tried \(attribution.attempted.map(\.displayName).joined(separator: ", then "))."
    }

    var body: some View {
        VStack(spacing: 16) {
            FBCard(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    FBInfoRow(
                        icon: failure.symbolName,
                        title: failure.title,
                        text: failure.message
                    )
                    if let attempted = attemptedNotice {
                        Text(attempted)
                            .font(.footnote)
                            .foregroundStyle(Color.fbMuted)
                    }
                }
            }
            if let onRetry {
                Button("Try again", action: onRetry)
                    .buttonStyle(.fb(.accent))
            }
            Button("Back", action: onBack)
                .buttonStyle(.fb(.secondary))
        }
        .padding(.top, 8)
    }
}

#if DEBUG
#Preview("Offline") {
    AnalysisErrorView(
        failure: .offline(.claude),
        attribution: AnalysisAttribution(first: .claude),
        onRetry: {},
        onBack: {}
    )
    .padding(16)
    .background(Color.fbBackground)
}

#Preview("No key") {
    AnalysisErrorView(failure: .missingAPIKey, attribution: nil, onRetry: nil, onBack: {})
        .padding(16)
        .background(Color.fbBackground)
}

#Preview("Every provider failed") {
    AnalysisErrorView(
        failure: .serviceUnavailable(.mistral),
        attribution: {
            var attribution = AnalysisAttribution(first: .claude)
            attribution.append(.gemini)
            attribution.append(.mistral)
            return attribution
        }(),
        onRetry: {},
        onBack: {}
    )
    .padding(16)
    .background(Color.fbBackground)
}
#endif
