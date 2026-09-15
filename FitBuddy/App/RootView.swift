import SwiftData
import SwiftUI

/// Root view gating app access on the 3-step onboarding flow (US-4), which is
/// coordinated by `OnboardingViewModel`: consent → Hevy key → LLM keys →
/// the tab bar with dashboard, analysis and settings (#27, #107).
struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    @StateObject private var onboardingViewModel = OnboardingViewModel()

    /// The visible tab. Owned here rather than in `MainTabView`, because
    /// deleting a key sends the user back into onboarding — a step change this
    /// view is the one to react to, and the next start must not land on the
    /// settings tab (#107).
    @State private var selectedTab: MainTab = .dashboard

    /// Bumped when the settings screen replaces the Hevy key, which drops the
    /// cached workouts. The dashboard stays alive on its tab and its own
    /// `.task` does not re-run, so without this it would sit on an empty
    /// cache (#91).
    @State private var dashboardReloadToken = 0

    var body: some View {
        Group {
            switch onboardingViewModel.step {
            case .loading:
                loadingView
            case .consent, .hevyKey, .llmKeys:
                OnboardingFlowView(viewModel: onboardingViewModel)
            case .completed:
                // The factories defer building the stores, the services and
                // the ViewModels until SwiftUI first creates each tab's state.
                MainTabView(
                    selection: $selectedTab,
                    analysisViewModel: makeAnalysisViewModel(),
                    makeDashboardViewModel: makeDashboardViewModel,
                    makeSettingsViewModel: makeSettingsViewModel,
                    makeWorkoutDetailViewModel: makeWorkoutDetailViewModel(for:),
                    makeExerciseListViewModel: makeExerciseListViewModel,
                    makeExerciseProgressionViewModel: makeExerciseProgressionViewModel(for:),
                    makeAnalysisHistoryViewModel: makeAnalysisHistoryViewModel,
                    reloadToken: dashboardReloadToken
                )
            }
        }
        // Exposes the coordinator to the rest of the app; the dashboard reaches
        // it through `onUnauthorized` below rather than the environment,
        // because the ViewModel is built here and must not depend on SwiftUI.
        .environmentObject(onboardingViewModel)
        // Deleting the Hevy key or all data drops the app back into
        // onboarding; the tab bar goes with it, and the selection is put back
        // so the next start lands on the dashboard, not in settings.
        .onChange(of: onboardingViewModel.step) { _, step in
            if step != .completed { selectedTab = .dashboard }
        }
        .task { await onboardingViewModel.bootstrap() }
    }

    /// Wires the dashboard to the cache and to Hevy (#28).
    ///
    /// Store, service and ViewModel share one `WorkoutStore` and one
    /// `SyncTimestampStore`, so the window the sync writes is exactly the one
    /// the dashboard reads back and both agree on the sync timestamp.
    private func makeDashboardViewModel() -> WorkoutListViewModel {
        let store = WorkoutStore(modelContainer: modelContext.container)
        let timestamps = SyncTimestampStore()
        let viewModel = WorkoutListViewModel(
            cache: store,
            syncer: Self.syncer(workouts: store, timestamps: timestamps),
            timestamps: timestamps
        )
        // Hevy rejected the stored key: `WorkoutSyncService` has already wiped it, so
        // the only thing left is to send the user back to step 2 (US-1 AC3).
        let coordinator = onboardingViewModel
        viewModel.onUnauthorized = { [weak coordinator] in
            await coordinator?.handleHevyUnauthorized()
        }
        return viewModel
    }

    /// The dashboard's sync for this launch. A UI test walking onboarding with
    /// a stubbed key gets a sync that reaches no network (#120) — the live one
    /// would answer that key with a 401 and drop the app back into step 2.
    private static func syncer(workouts: WorkoutStore, timestamps: SyncTimestampStore) -> any WorkoutSyncing {
        #if DEBUG
        if HevyStubbing.isActive() {
            return StubWorkoutSync()
        }
        #endif
        return WorkoutSyncService(workouts: workouts, timestamps: timestamps)
    }

    /// Wires the analysis tab to the cache and to Claude (#32).
    ///
    /// Its own `WorkoutStore` over the same container, since the analysis only
    /// reads — unlike the dashboard, it shares no write path with the sync.
    /// The rate-limit store *is* shared with `InferenceService`, so the label
    /// on screen and the service's own guard can never disagree.
    ///
    /// The result store goes over the same container as the two reset paths
    /// below, so a wipe removes exactly the history this screen would
    /// otherwise restore from (#97, #117).
    private func makeAnalysisViewModel() -> AnalysisViewModel {
        let rateLimit = AnalysisRateLimitStore()
        return AnalysisViewModel(
            cache: WorkoutStore(modelContainer: modelContext.container),
            inference: InferenceService(rateLimit: rateLimit),
            rateLimit: rateLimit,
            resultStore: AnalysisResultStore(modelContainer: modelContext.container)
        )
    }

    /// Wires the saved-analyses screen to the same store the analysis tab
    /// writes to (#117).
    ///
    /// A factory rather than a ready-made ViewModel: the screen exists only
    /// while the user is in it, and each push has to read the store fresh —
    /// a run in between adds a row, and a swipe in there removes one.
    private func makeAnalysisHistoryViewModel() -> AnalysisHistoryViewModel {
        AnalysisHistoryViewModel(store: AnalysisResultStore(modelContainer: modelContext.container))
    }

    /// Wires the workout detail screen to the cache (#98).
    ///
    /// A factory rather than a ready-made ViewModel: the screen exists only
    /// once a row is tapped, and the dashboard calls this per push. Its own
    /// `WorkoutStore` over the same container, like the analysis tab's —
    /// the detail screen only reads.
    private func makeWorkoutDetailViewModel(for workoutID: String) -> WorkoutDetailViewModel {
        WorkoutDetailViewModel(
            cache: WorkoutStore(modelContainer: modelContext.container),
            workoutID: workoutID
        )
    }

    /// Wires the exercise list to the cache (#37).
    ///
    /// A factory rather than a ready-made ViewModel: the screen exists only
    /// while the user is in it, and each push has to read the cache fresh — a
    /// sync in between changes what the window holds. Its own `WorkoutStore`
    /// over the same container, like the detail screen's — this one only reads.
    private func makeExerciseListViewModel() -> ExerciseListViewModel {
        ExerciseListViewModel(cache: WorkoutStore(modelContainer: modelContext.container))
    }

    /// One progression screen per tapped movement (US-9, #42). Reads the same
    /// container the list just read, so the curve and the row it was opened
    /// from describe the same window.
    private func makeExerciseProgressionViewModel(
        for exercise: ExerciseSummary
    ) -> ExerciseProgressionViewModel {
        ExerciseProgressionViewModel(
            cache: WorkoutStore(modelContainer: modelContext.container),
            exercise: exercise
        )
    }

    /// Wires the settings screen to the Keychain and to the two reset paths
    /// (#83). Both resets work on the same `ModelContainer` and the same
    /// `UserDefaults` as the dashboard's collaborators, so a wipe empties
    /// exactly the cache the dashboard reads back.
    private func makeSettingsViewModel() -> SettingsViewModel {
        let store = WorkoutStore(modelContainer: modelContext.container)
        let results = AnalysisResultStore(modelContainer: modelContext.container)
        let timestamps = SyncTimestampStore()
        let viewModel = SettingsViewModel(
            sessionReset: SessionResetService(workouts: store, results: results, timestamps: timestamps),
            dataReset: DataResetService(workouts: store, results: results, timestamps: timestamps)
        )
        let coordinator = onboardingViewModel
        // The hard logout already wiped the key and the cache; all that is left
        // is returning to step 2 (US-1 AC3). The quiet entry point, unlike the
        // dashboard's above: this user pressed the button themselves.
        viewModel.onHevyKeyDeleted = { [weak coordinator] in
            await coordinator?.handleHevyKeyDeleted()
        }
        viewModel.onDataDeleted = { [weak coordinator] in
            coordinator?.handleDataReset()
        }
        // A key was stored but the session did not end, so onboarding stays
        // out of it: the dashboard simply has to refill the cache it lost.
        viewModel.onHevyKeyStored = { dashboardReloadToken += 1 }
        return viewModel
    }

    /// Shown while the coordinator is still resolving the persisted state.
    private var loadingView: some View {
        FBSpinner()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fbBackground)
    }
}

#Preview {
    // RootView reaches for the SwiftData container once onboarding is
    // complete; without one the preview traps on a dev machine that already
    // has consent and both keys stored. `AnalysisResult` is listed too — the
    // analysis tab restores from it, and a container without the entity
    // would fail that fetch (#97).
    RootView()
        .modelContainer(for: [Workout.self, AnalysisResult.self], inMemory: true)
}
