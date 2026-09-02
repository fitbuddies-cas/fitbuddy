import SwiftData
import SwiftUI

/// Root view gating app access on the 3-step onboarding flow (US-4), which is
/// coordinated by `OnboardingViewModel`: consent → Hevy key → LLM keys →
/// dashboard (#27).
struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    @StateObject private var onboardingViewModel = OnboardingViewModel()

    /// Whether the settings sheet (#83) is presented. Owned here rather than in
    /// `DashboardView`, because deleting a key sends the user back into
    /// onboarding — a step change this view is the one to react to.
    @State private var showsSettings = false

    /// Bumped when the settings screen replaces the Hevy key, which drops the
    /// cached workouts. The dashboard's own `.task` does not re-run when the
    /// sheet closes, so without this it would sit on an empty cache (#91).
    @State private var dashboardReloadToken = 0

    var body: some View {
        Group {
            switch onboardingViewModel.step {
            case .loading:
                loadingView
            case .consent, .hevyKey, .llmKeys:
                OnboardingFlowView(viewModel: onboardingViewModel)
            case .completed:
                // The autoclosure defers building the store, the service and
                // the ViewModel until SwiftUI first creates the dashboard's
                // state.
                DashboardView(
                    viewModel: makeDashboardViewModel(),
                    analysisViewModel: makeAnalysisViewModel(),
                    reloadToken: dashboardReloadToken,
                    onOpenSettings: { showsSettings = true }
                )
            }
        }
        // Exposes the coordinator to the rest of the app; the dashboard reaches
        // it through `onUnauthorized` below rather than the environment,
        // because the ViewModel is built here and must not depend on SwiftUI.
        .environmentObject(onboardingViewModel)
        .sheet(isPresented: $showsSettings) {
            SettingsView(viewModel: makeSettingsViewModel())
        }
        // Deleting the Hevy key or all data drops the app back into
        // onboarding; the settings sheet must not stay up over it.
        .onChange(of: onboardingViewModel.step) { _, step in
            if step != .completed { showsSettings = false }
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
            syncer: HevyService(workouts: store, timestamps: timestamps),
            timestamps: timestamps
        )
        // Hevy rejected the stored key: `HevyService` has already wiped it, so
        // the only thing left is to send the user back to step 2 (US-1 AC3).
        let coordinator = onboardingViewModel
        viewModel.onUnauthorized = { [weak coordinator] in
            await coordinator?.handleHevyUnauthorized()
        }
        return viewModel
    }

    /// Wires the analysis sheet to the cache and to Claude (#32).
    ///
    /// Its own `WorkoutStore` over the same container, since the analysis only
    /// reads — unlike the dashboard, it shares no write path with the sync.
    /// The cooldown store *is* shared with `InferenceService`, so the label on
    /// screen and the service's own 6h guard can never disagree.
    ///
    /// The result store goes over the same container as the two reset paths
    /// below, so a wipe removes exactly the recommendation this screen would
    /// otherwise restore (#97).
    private func makeAnalysisViewModel() -> AnalysisViewModel {
        let cooldown = AnalysisCooldownStore()
        return AnalysisViewModel(
            cache: WorkoutStore(modelContainer: modelContext.container),
            inference: InferenceService(cooldown: cooldown),
            cooldown: cooldown,
            resultStore: AnalysisResultStore(modelContainer: modelContext.container)
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
        // is returning to step 2 — the same path an HTTP 401 takes (US-1 AC3).
        viewModel.onHevyKeyDeleted = { [weak coordinator] in
            await coordinator?.handleHevyUnauthorized()
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
    // analysis sheet restores from it, and a container without the entity
    // would fail that fetch (#97).
    RootView()
        .modelContainer(for: [Workout.self, AnalysisResult.self], inMemory: true)
}
