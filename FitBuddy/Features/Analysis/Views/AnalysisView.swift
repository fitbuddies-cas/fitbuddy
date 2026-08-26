import SwiftUI

/// The on-demand AI analysis screen (US-3, #32).
///
/// Presented as a sheet from the dashboard. Renders `AnalysisViewModel`'s
/// state and nothing else: the spinner appears the moment `start()` publishes
/// `.loading`, the recommendation grows chunk by chunk while `.streaming`, and
/// the cancel button joins the spinner once the run has gone 30s without a
/// first token (US-3 AC1).
struct AnalysisView: View {
    @StateObject private var viewModel: AnalysisViewModel
    @Environment(\.dismiss) private var dismiss

    /// - Parameter viewModel: Built lazily — the autoclosure is evaluated once,
    ///   when SwiftUI first creates the view's state, so presenting the sheet
    ///   from a parent's `body` does not rebuild it on every render.
    init(viewModel: @autoclosure @escaping () -> AnalysisViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .background(Color.fbBackground)
            .navigationTitle("AI analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Leaving the screen must not leave a request running
                        // in the background: the cooldown is spent either way,
                        // but a stream nobody reads is pure cost.
                        viewModel.cancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                    }
                    .tint(Color.fbInk)
                    .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        // Keeps the cooldown label counting down for as long as the sheet is
        // open; cancelled with the view.
        .task { await viewModel.trackCooldown() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            AnalysisIntroView(
                cooldownMessage: viewModel.cooldownMessage,
                canStart: viewModel.canStartAnalysis,
                onStart: start
            )
        case .loading:
            AnalysisProgressView(
                text: nil,
                isTakingLong: viewModel.isTakingLong,
                onCancel: viewModel.cancel
            )
        case .streaming(let text):
            AnalysisProgressView(
                text: text,
                isTakingLong: viewModel.isTakingLong,
                onCancel: viewModel.cancel
            )
        case .result(let text):
            AnalysisResultView(text: text)
        case .error(let failure):
            AnalysisErrorView(
                failure: failure,
                onRetry: failure.isRetryable ? start : nil,
                onDismiss: { viewModel.reset() }
            )
        }
    }

    /// The bar under the recommendation: the two feedback buttons while a
    /// result is showing (US-3 AC9), otherwise the cooldown label — and
    /// nothing at all while a run is in flight, where neither applies.
    @ViewBuilder
    private var footer: some View {
        switch viewModel.state {
        case .result:
            AnalysisFeedbackBar(
                selected: viewModel.feedback,
                cooldownMessage: viewModel.cooldownMessage,
                onSelect: { verdict in Task { await viewModel.submitFeedback(verdict) } }
            )
        case .idle, .error:
            if let cooldownMessage = viewModel.cooldownMessage {
                cooldownBar(cooldownMessage)
            }
        case .loading, .streaming:
            EmptyView()
        }
    }

    private func cooldownBar(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .fbTabularNumbers()
            .foregroundStyle(Color.fbInkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(.bar)
    }

    private func start() {
        Task { await viewModel.start() }
    }
}

#if DEBUG
#Preview("Ready") {
    AnalysisView(viewModel: AnalysisViewModel(
        cache: PreviewWorkoutCache.filled,
        inference: PreviewAnalysisStreamer.recommendation
    ))
}

/// Tapping "Analyze with AI" here shows the cancel button after 2s instead of
/// 30, on a stream that never answers.
#Preview("Taking long") {
    AnalysisView(viewModel: AnalysisViewModel(
        cache: PreviewWorkoutCache.filled,
        inference: PreviewAnalysisStreamer.silent,
        slowThreshold: 2
    ))
}
#endif
