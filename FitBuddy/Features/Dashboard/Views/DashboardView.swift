import SwiftUI

/// The dashboard for the last 90 days (US-2): total volume, training frequency,
/// muscle-group distribution and the recent sessions.
///
/// Renders `WorkoutListViewModel`'s state and nothing else. The content always
/// comes from the local cache, so it looks the same whether the last sync just
/// finished or the device has been offline for days; `SyncStatusView` on top
/// says which of the two it is (#28).
struct DashboardView: View {
    @StateObject private var viewModel: WorkoutListViewModel

    /// Built here rather than inside the sheet's closure, so the running
    /// analysis and its cooldown survive the sheet being dismissed and
    /// reopened.
    @StateObject private var analysisViewModel: AnalysisViewModel

    @State private var showsAnalysis = false

    /// - Parameters:
    ///   - viewModel: Built lazily — the autoclosure is evaluated once, when
    ///     SwiftUI first creates the view's state, so wiring it up in a
    ///     parent's `body` does not rebuild it on every render.
    ///   - analysisViewModel: Same, for the analysis sheet (#32).
    init(
        viewModel: @autoclosure @escaping () -> WorkoutListViewModel,
        analysisViewModel: @autoclosure @escaping () -> AnalysisViewModel
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _analysisViewModel = StateObject(wrappedValue: analysisViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Held back until the first cache read has resolved. Before
                    // that `lastSync` is still nil and the strip would claim
                    // "Never synced" for a frame or two — to a user who synced
                    // yesterday. The spinner below says the same thing without
                    // asserting anything false.
                    if viewModel.state != .loading {
                        SyncStatusView(
                            status: viewModel.syncStatus,
                            lastSync: viewModel.lastSync,
                            onRetry: { Task { await viewModel.refresh() } }
                        )
                    }
                    // Only with data behind it: an analysis of an empty or
                    // unreadable cache has nothing to say, and the failure it
                    // would produce is one the dashboard already explains.
                    if viewModel.state.hasWorkouts {
                        AnalysisCTACard { showsAnalysis = true }
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color.fbBackground)
            .navigationTitle("Dashboard")
            .refreshable { await viewModel.refresh() }
        }
        .task { await viewModel.refresh() }
        .sheet(isPresented: $showsAnalysis) {
            AnalysisView(viewModel: analysisViewModel)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            FBSpinner()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        case .loaded(let workouts, let metrics):
            DashboardContentView(workouts: workouts, metrics: metrics)
        case .empty:
            DashboardEmptyView()
        case .failed:
            failureView
        }
    }

    /// The cache could not be read. Kept distinct from the empty state on
    /// purpose: claiming "no training data" for a broken store would tell the
    /// user something false about their own training.
    private var failureView: some View {
        FBCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                FBInfoRow(
                    icon: "exclamationmark.triangle",
                    title: "Your training data could not be read",
                    text: """
                    The local cache on this device is unavailable. Pull to refresh — \
                    if that does not help, restarting FitBuddy usually does.
                    """
                )
                Button("Try again") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(FBButtonStyle(kind: .secondary))
            }
        }
        .padding(.top, 40)
    }
}

#if DEBUG
#Preview("With data") {
    DashboardView(
        viewModel: WorkoutListViewModel(cache: PreviewWorkoutCache.filled),
        analysisViewModel: AnalysisViewModel(
            cache: PreviewWorkoutCache.filled,
            inference: PreviewAnalysisStreamer.recommendation
        )
    )
}

#Preview("Empty") {
    DashboardView(
        viewModel: WorkoutListViewModel(cache: PreviewWorkoutCache.empty),
        analysisViewModel: AnalysisViewModel(
            cache: PreviewWorkoutCache.empty,
            inference: PreviewAnalysisStreamer.recommendation
        )
    )
}
#endif
