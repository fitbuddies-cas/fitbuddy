import SwiftUI

/// The on-demand AI analysis screen (US-3, #32).
///
/// Presented as a sheet from the dashboard. Renders `AnalysisViewModel`'s
/// state and nothing else: the spinner appears the moment `start()` publishes
/// `.loading`, the recommendation grows chunk by chunk while `.streaming`, and
/// the cancel button joins the spinner once the run has gone 30s without a
/// first token (US-3 AC1).
struct AnalysisView: View {
    /// Observed, not owned: the view model belongs to the presenting dashboard,
    /// which keeps it alive across sheet presentations so a run survives a
    /// dismissed sheet.
    @ObservedObject var viewModel: AnalysisViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Above the answer rather than under it: the period the
                    // recommendation rests on has to be known while reading it,
                    // not after (#87).
                    if viewModel.state.text != nil {
                        AnalysisWindowNote(window: viewModel.window)
                    }
                    content
                }
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
        // Brings back the last recommendation, so the cooldown does not leave a
        // returning user with a countdown and nothing to read (US-3 AC10). Its
        // own `.task`, because `trackCooldown()` never returns — and here
        // rather than in `DashboardView`, whose `reloadToken` path drops
        // exactly this state when the Hevy key changes (#91).
        .task { await viewModel.restore() }
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
                provider: viewModel.attribution?.provider,
                isTakingLong: viewModel.isTakingLong,
                onCancel: viewModel.cancel
            )
        case .streaming(let text):
            AnalysisProgressView(
                text: text,
                provider: viewModel.attribution?.provider,
                isTakingLong: viewModel.isTakingLong,
                onCancel: viewModel.cancel
            )
        case .result(let text):
            AnalysisResultView(
                text: text,
                attribution: viewModel.attribution,
                age: viewModel.resultAge,
                // Offered only while a new run is actually possible: during the
                // cooldown the intro screen would be a dead end with the same
                // countdown on it, and the recommendation the user still has is
                // the more useful thing to keep on screen (#97).
                onNewAnalysis: viewModel.canStartAnalysis ? { viewModel.reset() } : nil
            )
        case .error(let failure):
            AnalysisErrorView(
                failure: failure,
                attribution: viewModel.attribution,
                onRetry: failure.isRetryable ? start : nil,
                // Not a bare `reset()`: leaving the error screen must be
                // able to put the last stored recommendation back, so the
                // user is not left with a countdown and an empty screen (#97).
                onBack: { Task { await viewModel.dismissFailure() } }
            )
        }
    }

    /// The bar under the recommendation: the two feedback buttons while a
    /// result is showing (US-3 AC9), otherwise the cooldown label — and
    /// nothing at all while a run is in flight, where neither applies.
    ///
    /// `.idle` is deliberately not in the cooldown branch: `AnalysisIntroView`
    /// already prints the same label under its button, and repeating it in the
    /// bottom bar would show the user the same sentence twice. In `.error` the
    /// repetition is wanted — `AnalysisFailure.cooldownActive` names the time,
    /// the label next to it keeps ticking.
    @ViewBuilder
    private var footer: some View {
        switch viewModel.state {
        case .result:
            AnalysisFeedbackBar(
                selected: viewModel.feedback,
                cooldownMessage: viewModel.cooldownMessage,
                onSelect: { verdict in Task { await viewModel.submitFeedback(verdict) } }
            )
        case .error:
            if let cooldownMessage = viewModel.cooldownMessage {
                cooldownBar(cooldownMessage)
            }
        case .idle, .loading, .streaming:
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
/// Holds the view model for the previews the way the dashboard does in the app,
/// so `AnalysisView` gets an instance that outlives a body re-evaluation.
private struct AnalysisViewPreviewHost: View {
    @StateObject private var viewModel: AnalysisViewModel

    init(viewModel: @autoclosure @escaping () -> AnalysisViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        AnalysisView(viewModel: viewModel)
    }
}

#Preview("Ready") {
    AnalysisViewPreviewHost(viewModel: AnalysisViewModel(
        cache: PreviewWorkoutCache.filled,
        inference: PreviewAnalysisStreamer.recommendation
    ))
}

/// Tapping "Analyze with AI" here has Claude give way to Gemini before the
/// answer arrives, so the badge and the fallback notice are both visible.
#Preview("Provider fallback") {
    AnalysisViewPreviewHost(viewModel: AnalysisViewModel(
        cache: PreviewWorkoutCache.filled,
        inference: PreviewAnalysisStreamer.fallback
    ))
}

/// Tapping "Analyze with AI" here shows the cancel button after 2s instead of
/// 30, on a stream that never answers.
#Preview("Taking long") {
    AnalysisViewPreviewHost(viewModel: AnalysisViewModel(
        cache: PreviewWorkoutCache.filled,
        inference: PreviewAnalysisStreamer.silent,
        slowThreshold: 2
    ))
}
#endif
