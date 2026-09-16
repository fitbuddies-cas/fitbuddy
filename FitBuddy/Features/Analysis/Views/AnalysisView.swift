import SwiftUI

/// The on-demand AI analysis screen (US-3, #32).
///
/// Its own tab in `MainTabView` (#107). Renders `AnalysisViewModel`'s state
/// and nothing else: the spinner appears the moment `start()` publishes
/// `.running` and stays until the whole answer is in, the answer then appears
/// in one step (#178), and the cancel button joins the spinner once the run
/// has gone 30s without an answer (US-3 AC1).
///
/// Switching tabs does not cancel a running stream: in a tab bar, tapping
/// away is not leaving the screen, and the tokens are spent either way. The
/// cancel button in the progress view is the only way to abort.
struct AnalysisView: View {
    /// Observed, not owned: the view model belongs to `MainTabView`, which
    /// keeps it alive across tab switches so a run and its countdown survive.
    @ObservedObject var viewModel: AnalysisViewModel
    /// Builds the history screen's view model, once per push (#117). A factory
    /// rather than a ready-made instance: the screen exists only while the user
    /// is in it, and it must read the store fresh when they open it.
    let makeHistoryViewModel: () -> AnalysisHistoryViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.fbBackground)
            .navigationTitle("AI analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { historyLink }
            .navigationDestination(for: AnalysisRoute.self) { route in
                switch route {
                case .history:
                    AnalysisHistoryView(viewModel: makeHistoryViewModel())
                        // The user may have deleted the analysis on screen, or
                        // the last one behind it. Re-reading on the way back
                        // keeps this screen and the link agreeing with the
                        // store (#117).
                        .onDisappear { Task { await viewModel.refreshHistory() } }
                }
            }
            // A bar rather than a plain inset: the content underneath gets the
            // same soft scroll-edge fade the tab bar has, so the footer sits
            // with the glass instead of stacking a second opaque strip on it.
            .safeAreaBar(edge: .bottom) { footer }
        }
        // Keeps the lock label counting down for as long as the tab is
        // visible; cancelled with the view.
        .task { await viewModel.trackLock() }
        // Brings back the newest recommendation, so a returning user lands on
        // the answer they paid for rather than on the intro (US-3 AC10). Its
        // own `.task`, because `trackLock()` never returns — and here
        // rather than in `DashboardView`, whose `reloadToken` path drops
        // exactly this state when the Hevy key changes (#91).
        .task { await viewModel.restore() }
    }

    /// The way into the saved analyses — shown only once there is more than
    /// one, because with a single one this screen already shows it.
    @ToolbarContentBuilder
    private var historyLink: some ToolbarContent {
        if viewModel.hasHistory {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AnalysisRoute.history) {
                    Label("Saved analyses", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            AnalysisIntroView(
                lockMessage: viewModel.lockMessage,
                canStart: viewModel.canStartAnalysis,
                onStart: start
            )
        case .running:
            AnalysisProgressView(
                provider: viewModel.attribution?.provider,
                isTakingLong: viewModel.isTakingLong,
                onCancel: viewModel.cancel
            )
        case .result(let outcome):
            // The context line travels into the result rather than sitting
            // above it: under a report it follows the verdict headline (US-14
            // AC1), and in both cases it comes before the recommendation is
            // read, not after (#87, #36).
            AnalysisResultView(
                outcome: outcome,
                context: viewModel.context,
                attribution: viewModel.attribution,
                age: viewModel.resultAge,
                // Offered only while a new run is actually possible: while the lock
                // holds, the intro screen would be a dead end with the same countdown
                // on it, and the recommendation the user still has is the more useful
                // thing to keep on screen (#97).
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

    /// The bar under the recommendation or the error: the lock label while a
    /// lock is running, and nothing at all while a run is in flight, where it
    /// does not apply.
    ///
    /// `.idle` is deliberately not in the lock branch: `AnalysisIntroView`
    /// already prints the same label under its button, and repeating it in the
    /// bottom bar would show the user the same sentence twice. In `.error` the
    /// repetition is wanted — `AnalysisFailure.lockActive` names the time,
    /// the label next to it keeps ticking.
    @ViewBuilder
    private var footer: some View {
        switch viewModel.state {
        case .result, .error:
            if let lockMessage = viewModel.lockMessage {
                lockBar(lockMessage)
            }
        case .idle, .running:
            EmptyView()
        }
    }

    private func lockBar(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .fbTabularNumbers()
            .foregroundStyle(Color.fbInkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
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
        AnalysisView(
            viewModel: viewModel,
            makeHistoryViewModel: { AnalysisHistoryViewModel(store: PreviewAnalysisResultStore()) }
        )
    }
}

#Preview("Ready") {
    AnalysisViewPreviewHost(viewModel: AnalysisViewModel(
        cache: PreviewWorkoutCache.filled,
        inference: PreviewAnalysisStreamer.recommendation
    ))
}

/// Two stored analyses, so the screen lands on the newest one and the way into
/// the saved ones appears in the toolbar (#117).
#Preview("With saved analyses") {
    AnalysisViewPreviewHost(viewModel: AnalysisViewModel(
        cache: PreviewWorkoutCache.filled,
        inference: PreviewAnalysisStreamer.recommendation,
        resultStore: PreviewAnalysisResultStore()
    ))
}

/// Tapping "Analyze with AI" here has Mistral answer in prose instead of a
/// report — the fallback of US-14 AC5.
#Preview("Prose answer") {
    AnalysisViewPreviewHost(viewModel: AnalysisViewModel(
        cache: PreviewWorkoutCache.filled,
        inference: PreviewAnalysisStreamer.prose
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
