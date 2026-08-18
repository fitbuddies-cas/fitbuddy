import SwiftData
import SwiftUI

/// Root view gating app access on the 3-step onboarding flow (US-4), which is
/// coordinated by `OnboardingViewModel`: consent → Hevy key → Claude key →
/// dashboard (#27).
struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    @StateObject private var onboardingViewModel = OnboardingViewModel()

    var body: some View {
        Group {
            switch onboardingViewModel.step {
            case .loading:
                loadingView
            case .consent, .hevyKey, .claudeKey:
                OnboardingFlowView(viewModel: onboardingViewModel)
            case .completed:
                // The autoclosure defers building the store and the ViewModel
                // until SwiftUI first creates the dashboard's state.
                DashboardView(
                    viewModel: WorkoutListViewModel(
                        cache: WorkoutStore(modelContainer: modelContext.container)
                    )
                )
            }
        }
        // Exposes the coordinator to future app surfaces — services reporting
        // an invalid Hevy key (HTTP 401, e.g. HevyService #25) call
        // `handleHevyUnauthorized()` through it.
        .environmentObject(onboardingViewModel)
        .task { await onboardingViewModel.bootstrap() }
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
