import SwiftUI

/// The failed run: what went wrong, and the one thing worth doing about it
/// (#32).
///
/// The wording, the symbol and whether a retry is offered all come from
/// `AnalysisFailure` — the view only lays them out.
struct AnalysisErrorView: View {
    let failure: AnalysisFailure
    /// `nil` for a failure a retry cannot fix (a missing or rejected key, an
    /// active cooldown), where a "Try again" button would only produce the
    /// same message again.
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            FBCard(padding: 18) {
                FBInfoRow(
                    icon: failure.symbolName,
                    title: failure.title,
                    text: failure.message
                )
            }
            if let onRetry {
                Button("Try again", action: onRetry)
                    .buttonStyle(.fb(.accent))
            }
            Button("Back", action: onDismiss)
                .buttonStyle(.fb(.secondary))
        }
        .padding(.top, 8)
    }
}

#if DEBUG
#Preview("Offline") {
    AnalysisErrorView(failure: .offline, onRetry: {}, onDismiss: {})
        .padding(16)
        .background(Color.fbBackground)
}

#Preview("No key") {
    AnalysisErrorView(failure: .missingAPIKey, onRetry: nil, onDismiss: {})
        .padding(16)
        .background(Color.fbBackground)
}
#endif
