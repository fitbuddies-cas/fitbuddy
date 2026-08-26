import SwiftData
import SwiftUI

/// Root view gating app access on the 3-step onboarding flow (US-4), which is
/// coordinated by `OnboardingViewModel`: consent → Hevy key → LLM keys →
/// dashboard (#27).
struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    @StateObject private var onboardingViewModel = OnboardingViewModel()

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
                    analysisViewModel: makeAnalysisViewModel()
                )
            }
        }
        // Exposes the coordinator to the rest of the app; the dashboard reaches
        // it through `onUnauthorized` below rather than the environment,
        // because the ViewModel is built here and must not depend on SwiftUI.
        .environmentObject(onboardingViewModel)
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
    private func makeAnalysisViewModel() -> AnalysisViewModel {
        let cooldown = AnalysisCooldownStore()
        return AnalysisViewModel(
            cache: WorkoutStore(modelContainer: modelContext.container),
            inference: InferenceService(cooldown: cooldown),
            cooldown: cooldown
        )
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
    // has consent and both keys stored.
    RootView()
        .modelContainer(for: Workout.self, inMemory: true)
}
