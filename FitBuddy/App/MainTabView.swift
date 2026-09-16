import SwiftUI

/// The tab bar shown once onboarding is complete (#107): Dashboard, Analysis
/// and Settings, each with its own `NavigationStack`.
///
/// Pure layout. The ViewModels are wired up in `RootView`, which owns the
/// SwiftData container; this view only holds the one that has to outlive a
/// tab switch — `AnalysisViewModel`, whose running stream must not restart because the user glanced at the dashboard.
///
/// The bar itself is left to the system: no appearance override and no
/// background of its own, so the Liquid Glass material shows the content
/// scrolling through underneath it. That is a deliberate departure from the
/// pre-glass mocks in `design/`, which draw flat surfaces.
struct MainTabView: View {
    @Binding var selection: MainTab
    /// The settings tab's navigation path, owned by the root so the
    /// dashboard's renewal banner can open the Strava screen (#144).
    @Binding var settingsPath: [SettingsRoute]

    /// Owned here rather than by `AnalysisView`, so the analysis tab can be
    /// left and re-entered without losing the run.
    @StateObject private var analysisViewModel: AnalysisViewModel

    private let makeDashboardViewModel: () -> WorkoutListViewModel
    private let makeSettingsViewModel: () -> SettingsViewModel
    private let makeStravaConnectionViewModel: @MainActor () -> StravaConnectionViewModel
    private let makePolarConnectionViewModel: @MainActor () -> PolarConnectionViewModel
    private let makeWorkoutDetailViewModel: (String) -> WorkoutDetailViewModel
    private let makeExerciseListViewModel: () -> ExerciseListViewModel
    private let makeExerciseProgressionViewModel: (ExerciseIdentity) -> ExerciseProgressionViewModel
    private let makeAnalysisHistoryViewModel: () -> AnalysisHistoryViewModel

    /// Changes whenever something outside the dashboard invalidated the cache —
    /// a replaced Hevy key (#91), a Strava connect or disconnect (#140).
    /// Passed through to the dashboard, and used here to drop the analysis
    /// built from the discarded cache.
    private let reloadToken: Int

    /// Where the dashboard's renewal banner leads (#144).
    private let onRenewSource: (ConnectorSource) -> Void

    /// - Parameters:
    ///   - selection: The visible tab, owned by the parent.
    ///   - analysisViewModel: Built lazily — the autoclosure is evaluated once,
    ///     when SwiftUI first creates this view's state.
    ///   - makeDashboardViewModel: Handed to `DashboardView`, which keeps the
    ///     result as its own state — see its initializer.
    ///   - makeSettingsViewModel: Same, for `SettingsView`.
    ///   - makeStravaConnectionViewModel: Handed on to `SettingsView`, called
    ///     once per push of the Strava connection screen (#140).
    ///   - makeWorkoutDetailViewModel: Called once per pushed session (#98).
    ///   - makeExerciseListViewModel: Called once per push of the exercise
    ///     list (#37).
    ///   - makeExerciseProgressionViewModel: Called once per pushed movement
    ///     (#42).
    ///   - makeAnalysisHistoryViewModel: Called once per push of the saved
    ///     analyses (#117).
    ///   - reloadToken: Defaults to a constant, so a preview never re-syncs.
    ///   - settingsPath: Defaults to a constant empty path, for previews.
    ///   - onRenewSource: Defaults to nothing, for previews.
    init(
        selection: Binding<MainTab>,
        settingsPath: Binding<[SettingsRoute]> = .constant([]),
        analysisViewModel: @autoclosure @escaping () -> AnalysisViewModel,
        makeDashboardViewModel: @escaping () -> WorkoutListViewModel,
        makeSettingsViewModel: @escaping () -> SettingsViewModel,
        makeStravaConnectionViewModel: @escaping @MainActor () -> StravaConnectionViewModel,
        makePolarConnectionViewModel: @escaping @MainActor () -> PolarConnectionViewModel,
        makeWorkoutDetailViewModel: @escaping (String) -> WorkoutDetailViewModel,
        makeExerciseListViewModel: @escaping () -> ExerciseListViewModel,
        makeExerciseProgressionViewModel: @escaping (ExerciseIdentity) -> ExerciseProgressionViewModel,
        makeAnalysisHistoryViewModel: @escaping () -> AnalysisHistoryViewModel,
        reloadToken: Int = 0,
        onRenewSource: @escaping (ConnectorSource) -> Void = { _ in }
    ) {
        _selection = selection
        _settingsPath = settingsPath
        _analysisViewModel = StateObject(wrappedValue: analysisViewModel())
        self.onRenewSource = onRenewSource
        self.makeDashboardViewModel = makeDashboardViewModel
        self.makeSettingsViewModel = makeSettingsViewModel
        self.makeStravaConnectionViewModel = makeStravaConnectionViewModel
        self.makePolarConnectionViewModel = makePolarConnectionViewModel
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
                    reloadToken: reloadToken,
                    onRenewSource: onRenewSource
                )
            }
            Tab("Analysis", systemImage: "sparkles", value: MainTab.analysis) {
                AnalysisView(
                    viewModel: analysisViewModel,
                    makeHistoryViewModel: makeAnalysisHistoryViewModel
                )
            }
            Tab("Settings", systemImage: "gearshape", value: MainTab.settings) {
                SettingsView(
                    viewModel: makeSettingsViewModel(),
                    path: $settingsPath,
                    makeStravaConnectionViewModel: makeStravaConnectionViewModel,
                    makePolarConnectionViewModel: makePolarConnectionViewModel
                )
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
    func discardCachedWorkouts(from source: ConnectorSource) async {}
    func deleteAllData() async {}
}

/// OAuth that never reaches a browser, so the Strava screen renders in a
/// preview without a sheet.
private struct PreviewStravaOAuthorizer: StravaOAuthorizing {
    func authorize(_ credentials: StravaClientCredentials) async throws -> ConnectorCredentials {
        throw StravaOAuthError.transport
    }

    func refresh(_ credentials: StravaClientCredentials, refreshToken: String) async throws -> ConnectorCredentials {
        throw StravaOAuthError.transport
    }
}

/// OAuth that never reaches a browser, so the Polar screen renders in a
/// preview without a sheet.
private struct PreviewPolarOAuthorizer: PolarOAuthorizing {
    func authorize(_ credentials: PolarClientCredentials) async throws -> ConnectorCredentials {
        throw PolarOAuthError.transport
    }

    func refresh(_ credentials: PolarClientCredentials, refreshToken: String) async throws -> ConnectorCredentials {
        throw PolarOAuthError.transport
    }
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
            makeStravaConnectionViewModel: {
                StravaConnectionViewModel(
                    oauth: PreviewStravaOAuthorizer(),
                    credentialStore: StravaCredentialStore(),
                    registry: ConnectorRegistry(),
                    sessionReset: PreviewResetService()
                )
            },
            makePolarConnectionViewModel: {
                PolarConnectionViewModel(
                    oauth: PreviewPolarOAuthorizer(),
                    credentialStore: PolarCredentialStore(),
                    registry: ConnectorRegistry(),
                    sessionReset: PreviewResetService()
                )
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
