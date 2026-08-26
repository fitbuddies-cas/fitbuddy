import SwiftUI

/// The screen while a run is in flight: the spinner that appears immediately
/// after the tap, the text as it arrives, and — once the run has gone 30s
/// without a first token — the reason and the cancel button (US-3 AC1, #32).
struct AnalysisProgressView: View {
    /// What has arrived so far, or `nil` while nothing has (the spinner phase).
    let text: String?
    let isTakingLong: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let text, !text.isEmpty {
                FBCard(padding: 18) {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Color.fbInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity)
            }
            if isTakingLong {
                slowNotice
                Button("Cancel analysis", action: onCancel)
                    .buttonStyle(.fb(.secondary))
            }
            // Repeated from the intro on purpose: waiting is exactly when the
            // user wonders what just left the phone.
            AnalysisPrivacyNote()
        }
        .animation(.easeOut(duration: 0.2), value: isTakingLong)
    }

    private var header: some View {
        HStack(spacing: 12) {
            FBSpinner(size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(text == nil ? "Analyzing your last 4 weeks" : "Writing your recommendation")
                    .font(.fbTitle)
                    .foregroundStyle(Color.fbInk)
                Text("Claude usually answers in a few seconds.")
                    .font(.footnote)
                    .foregroundStyle(Color.fbMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        // One announcement for the pair, so VoiceOver reads the state instead
        // of stepping through a spinner and two labels.
        .accessibilityElement(children: .combine)
    }

    /// Shown only after the slow threshold: naming the wait is what makes the
    /// cancel button below it an offer rather than a failure.
    private var slowNotice: some View {
        FBCard(padding: 16) {
            FBInfoRow(
                icon: "clock.badge.exclamationmark",
                title: "Analysis is taking longer than expected",
                text: "You can keep waiting, or cancel and try again."
            )
        }
    }
}

#if DEBUG
#Preview("Spinner") {
    AnalysisProgressView(text: nil, isTakingLong: false, onCancel: {})
        .padding(16)
        .background(Color.fbBackground)
}

#Preview("Streaming") {
    AnalysisProgressView(
        text: "Your last four weeks show 14 sessions with steady volume on chest and back",
        isTakingLong: false,
        onCancel: {}
    )
    .padding(16)
    .background(Color.fbBackground)
}

#Preview("Taking long") {
    AnalysisProgressView(text: nil, isTakingLong: true, onCancel: {})
        .padding(16)
        .background(Color.fbBackground)
}
#endif
