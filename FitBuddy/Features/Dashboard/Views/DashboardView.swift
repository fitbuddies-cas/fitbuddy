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

    /// Builds the ViewModel behind the exercise list (#37) — same reasoning,
    /// and likewise called once per push rather than once per render.
    private let makeExerciseListViewModel: () -> ExerciseListViewModel

    /// Changes whenever something outside the dashboard invalidated the cache —
    /// today only a replaced Hevy key (#91). Its value carries no meaning; the
    /// change itself is the signal to sync again.
    private let reloadToken: Int

    /// The `reloadToken` the dashboard last synced for. `.task(id:)` restarts
    /// whenever the view re-appears, and inside a `TabView` that is every
    /// return to this tab — without this, each tab switch would drop the
    /// loaded state back to `.loading` and start a full Hevy sync.
    @State private var loadedToken: Int?

    /// - Parameters:
    ///   - viewModel: Built lazily — the autoclosure is evaluated once, when
    ///     SwiftUI first creates the view's state, so wiring it up in a
    ///     parent's `body` does not rebuild it on every render.
    ///   - makeWorkoutDetailViewModel: Called once per push, not per rendered
    ///     row — see `.navigationDestination` below.
    ///   - makeExerciseListViewModel: Called once per push of the exercise
    ///     list (#37).
    ///   - reloadToken: Defaults to a constant, so a preview or a test that
    ///     has no cache-invalidating parent never re-syncs.
    init(
        viewModel: @autoclosure @escaping () -> WorkoutListViewModel,
        makeWorkoutDetailViewModel: @escaping (String) -> WorkoutDetailViewModel,
        makeExerciseListViewModel: @escaping () -> ExerciseListViewModel,
        reloadToken: Int = 0
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.makeWorkoutDetailViewModel = makeWorkoutDetailViewModel
        self.makeExerciseListViewModel = makeExerciseListViewModel
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
            .navigationDestination(for: DashboardRoute.self) { route in
                switch route {
                case .exercises:
                    ExerciseListView(viewModel: makeExerciseListViewModel())
                }
            }
            .toolbar { exercisesLink }
            .refreshable { await viewModel.refresh() }
        }
        // `.task(id:)` rather than a plain `.task`: the first run is the
        // dashboard appearing, every later one is a cache another screen
        // invalidated (#91). The guard keeps it at that — a tab switch
        // re-appears the view and restarts the task, but not the sync.
        // Pull-to-refresh stays the manual way to sync again.
        .task(id: reloadToken) {
            guard loadedToken != reloadToken else { return }
            loadedToken = reloadToken
            await viewModel.reload()
        }
    }

    /// Opens the searchable exercise list (US-7). Only with data behind it:
    /// over an empty or unreadable cache the list has nothing to search, and
    /// the dashboard underneath already explains why.
    @ToolbarContentBuilder
    private var exercisesLink: some ToolbarContent {
        if case .loaded = viewModel.state {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: DashboardRoute.exercises) {
                    Label("Exercises", systemImage: "list.bullet")
                }
            }
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
        makeWorkoutDetailViewModel: { id in
            WorkoutDetailViewModel(cache: PreviewWorkoutDetailCache.filled, workoutID: id)
        },
        makeExerciseListViewModel: { ExerciseListViewModel(cache: PreviewExerciseCache.filled) }
    )
}

#Preview("Empty") {
    DashboardView(
        viewModel: WorkoutListViewModel(cache: PreviewWorkoutCache.empty),
        makeWorkoutDetailViewModel: { id in
            WorkoutDetailViewModel(cache: PreviewWorkoutDetailCache.filled, workoutID: id)
        },
        makeExerciseListViewModel: { ExerciseListViewModel(cache: PreviewExerciseCache.filled) }
    )
}
#endif
