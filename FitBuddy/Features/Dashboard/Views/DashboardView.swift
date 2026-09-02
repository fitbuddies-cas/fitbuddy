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

    /// Builds the ViewModel behind the workout detail screen for the tapped
    /// session (#98). Handed in rather than reached for through
    /// `@Environment(\.modelContext)`: `RootView` owns the container and builds
    /// every other ViewModel too, and a View that assembles its own SwiftData
    /// dependencies is one no preview can stand up.
    private let makeWorkoutDetailViewModel: (String) -> WorkoutDetailViewModel

    /// Changes whenever something outside the dashboard invalidated the cache —
    /// today only a replaced Hevy key (#91). Its value carries no meaning; the
    /// change itself is the signal to sync again.
    private let reloadToken: Int

    /// - Parameters:
    ///   - viewModel: Built lazily — the autoclosure is evaluated once, when
    ///     SwiftUI first creates the view's state, so wiring it up in a
    ///     parent's `body` does not rebuild it on every render.
    ///   - makeWorkoutDetailViewModel: Called once per push, not per rendered
    ///     row — see `.navigationDestination` below.
    ///   - reloadToken: Defaults to a constant, so a preview or a test that
    ///     has no cache-invalidating parent never re-syncs.
    init(
        viewModel: @autoclosure @escaping () -> WorkoutListViewModel,
        makeWorkoutDetailViewModel: @escaping (String) -> WorkoutDetailViewModel,
        reloadToken: Int = 0
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.makeWorkoutDetailViewModel = makeWorkoutDetailViewModel
        self.reloadToken = reloadToken
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
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color.fbBackground)
            .navigationTitle("Dashboard")
            // By value, so the destination is built when a row is tapped
            // rather than once per row while the list renders (#98). Reading
            // it back costs no sync — the session is already in the cache.
            .navigationDestination(for: WorkoutSummary.self) { workout in
                WorkoutDetailView(viewModel: makeWorkoutDetailViewModel(workout.id))
            }
            .refreshable { await viewModel.refresh() }
        }
        // `.task(id:)` rather than a plain `.task`: the first run is the
        // dashboard appearing, every later one is a cache another screen
        // invalidated while this view stayed alive (#91).
        .task(id: reloadToken) { await viewModel.reload() }
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
        makeWorkoutDetailViewModel: { id in
            WorkoutDetailViewModel(cache: PreviewWorkoutDetailCache.filled, workoutID: id)
        }
    )
}

#Preview("Empty") {
    DashboardView(
        viewModel: WorkoutListViewModel(cache: PreviewWorkoutCache.empty),
        makeWorkoutDetailViewModel: { id in
            WorkoutDetailViewModel(cache: PreviewWorkoutDetailCache.filled, workoutID: id)
        }
    )
}
#endif
