import SwiftUI

/// The tab bar shown once onboarding is complete (#107): Dashboard, Analysis
/// and Settings, each with its own `NavigationStack`.
///
/// Pure layout. The ViewModels are wired up in `RootView`, which owns the
/// SwiftData container; this view only holds the one that has to outlive a
/// tab switch — `AnalysisViewModel`, whose running stream and countdown must
/// not restart because the user glanced at the dashboard.
///
/// The bar itself is left to the system: no appearance override and no
/// background of its own, so the Liquid Glass material shows the content
/// scrolling through underneath it. That is a deliberate departure from the
/// pre-glass mocks in `design/`, which draw flat surfaces.
struct MainTabView: View {
    @Binding var selection: MainTab

    /// Owned here rather than by `AnalysisView`, so the analysis tab can be
    /// left and re-entered without losing the run or the countdown.
    @StateObject private var analysisViewModel: AnalysisViewModel

    private let makeDashboardViewModel: () -> WorkoutListViewModel
    private let makeSettingsViewModel: () -> SettingsViewModel
    private let makeWorkoutDetailViewModel: (String) -> WorkoutDetailViewModel
    private let makeExerciseListViewModel: () -> ExerciseListViewModel
    private let makeExerciseProgressionViewModel: (ExerciseIdentity) -> ExerciseProgressionViewModel
    private let makeAnalysisHistoryViewModel: () -> AnalysisHistoryViewModel

    /// Changes whenever something outside the dashboard invalidated the cache —
    /// today only a replaced Hevy key (#91). Passed through to the dashboard,
    /// and used here to drop the analysis built from the discarded cache.
    private let reloadToken: Int

    /// - Parameters:
    ///   - selection: The visible tab, owned by the parent.
    ///   - analysisViewModel: Built lazily — the autoclosure is evaluated once,
    ///     when SwiftUI first creates this view's state.
    ///   - makeDashboardViewModel: Handed to `DashboardView`, which keeps the
    ///     result as its own state — see its initializer.
    ///   - makeSettingsViewModel: Same, for `SettingsView`.
    ///   - makeWorkoutDetailViewModel: Called once per pushed session (#98).
    ///   - makeExerciseListViewModel: Called once per push of the exercise
    ///     list (#37).
    ///   - makeExerciseProgressionViewModel: Called once per pushed movement
    ///     (#42).
    ///   - makeAnalysisHistoryViewModel: Called once per push of the saved
    ///     analyses (#117).
    ///   - reloadToken: Defaults to a constant, so a preview never re-syncs.
    init(
        selection: Binding<MainTab>,
        analysisViewModel: @autoclosure @escaping () -> AnalysisViewModel,
        makeDashboardViewModel: @escaping () -> WorkoutListViewModel,
        makeSettingsViewModel: @escaping () -> SettingsViewModel,
        makeWorkoutDetailViewModel: @escaping (String) -> WorkoutDetailViewModel,
        makeExerciseListViewModel: @escaping () -> ExerciseListViewModel,
        makeExerciseProgressionViewModel: @escaping (ExerciseIdentity) -> ExerciseProgressionViewModel,
        makeAnalysisHistoryViewModel: @escaping () -> AnalysisHistoryViewModel,
        reloadToken: Int = 0
    ) {
        _selection = selection
        _analysisViewModel = StateObject(wrappedValue: analysisViewModel())
        self.makeDashboardViewModel = makeDashboardViewModel
        self.makeSettingsViewModel = makeSettingsViewModel
        self.makeWorkoutDetailViewModel = makeWorkoutDetailViewModel
        self.makeExerciseListViewModel = makeExerciseListViewModel
        self.makeExerciseProgressionViewModel = makeExerciseProgressionViewModel
        self.makeAnalysisHistoryViewModel = makeAnalysisHistoryViewModel
        self.reloadToken = reloadToken
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Dashboard", systemImage: "house", value: MainTab.dashboard) {
                DashboardView(
                    viewModel: makeDashboardViewModel(),
                    makeWorkoutDetailViewModel: makeWorkoutDetailViewModel,
                    makeExerciseListViewModel: makeExerciseListViewModel,
                    makeExerciseProgressionViewModel: makeExerciseProgressionViewModel,
                    reloadToken: reloadToken
                )
            }
            Tab("Analysis", systemImage: "sparkles", value: MainTab.analysis) {
                AnalysisView(
                    viewModel: analysisViewModel,
                    makeHistoryViewModel: makeAnalysisHistoryViewModel
                )
            }
            Tab("Settings", systemImage: "gearshape", value: MainTab.settings) {
                SettingsView(viewModel: makeSettingsViewModel())
            }
        }
        // No `.tabBarMinimizeBehavior`: on iOS 26 the minimized bar collapses
        // into a pill on the leading edge while scrolling, which reads as the
        // bar sliding away. The three tabs stay put instead.
        .tint(Color.fbAccent)
        // The recommendation on the analysis tab was built from the cache that
        // was just discarded, and that view model outlives the tab — without
        // this it would keep showing the previous account's analysis. Its
        // stored copy is already gone by the time the token changes:
        // `SessionResetService.discardCachedWorkouts()` drops the whole history
        // with the cache, so `reset()` here has nothing left to restore from
        // (#97, #117).
        .onChange(of: reloadToken) { _, _ in
            analysisViewModel.cancel()
            analysisViewModel.reset()
        }
    }
}

#if DEBUG
/// Reset paths that do nothing, so the settings tab renders without a
/// SwiftData container.
private struct PreviewResetService: SessionResetting, DataResetting {
    func hardLogout() async {}
    func discardCachedWorkouts() async {}
    func deleteAllData() async {}
}

/// Holds the selection for the preview the way `RootView` does in the app.
private struct MainTabViewPreviewHost: View {
    @State private var selection: MainTab = .dashboard

    var body: some View {
        MainTabView(
            selection: $selection,
            analysisViewModel: AnalysisViewModel(
                cache: PreviewWorkoutCache.filled,
                inference: PreviewAnalysisStreamer.recommendation
            ),
            makeDashboardViewModel: { WorkoutListViewModel(cache: PreviewWorkoutCache.filled) },
            makeSettingsViewModel: {
                SettingsViewModel(sessionReset: PreviewResetService(), dataReset: PreviewResetService())
            },
            makeWorkoutDetailViewModel: { id in
                WorkoutDetailViewModel(cache: PreviewWorkoutDetailCache.filled, workoutID: id)
            },
            makeExerciseListViewModel: {
                ExerciseListViewModel(cache: PreviewExerciseCache.filled)
            },
            makeExerciseProgressionViewModel: { _ in PreviewProgressionCache.rising },
            makeAnalysisHistoryViewModel: {
                AnalysisHistoryViewModel(store: PreviewAnalysisResultStore())
            }
        )
    }
}

#Preview {
    MainTabViewPreviewHost()
}
#endif
