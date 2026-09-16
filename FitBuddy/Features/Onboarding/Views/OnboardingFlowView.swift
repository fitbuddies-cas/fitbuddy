import SwiftUI

/// Hosts the 4-step onboarding flow (US-4, US-13) in a single `NavigationStack`:
/// consent at the root, the two key screens pushed on top as the coordinator
/// advances. Navigation is forward-only — completed steps are gates the user
/// cannot revisit, so the back button is hidden and the path is derived from
/// `OnboardingViewModel.step` instead of being user-driven.
struct OnboardingFlowView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        NavigationStack(path: path) {
            ConsentView(viewModel: viewModel.consentViewModel)
                .navigationDestination(for: OnboardingStep.self) { step in
                    destination(for: step)
                        .navigationBarBackButtonHidden(true)
                        // Hevy/LLM screens own their look end-to-end (custom
                        // step indicator, no title) — without this the stack
                        // still renders an empty system nav bar above them.
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
    }

    @ViewBuilder
    private func destination(for step: OnboardingStep) -> some View {
        switch step {
        case .hevyKey:
            HevyKeyEntryView(viewModel: viewModel.hevyKeyViewModel)
        case .llmKeys:
            LLMKeysView(viewModel: viewModel.llmKeysViewModel)
        case .trainingProfile:
            TrainingProfileView(viewModel: viewModel.trainingProfileViewModel)
        case .loading, .consent, .completed:
            // Never pushed: .loading/.completed are handled by RootView and
            // .consent is the stack's root.
            EmptyView()
        }
    }

    /// Push path derived from the coordinator's step. The setter discards
    /// pops — the flow cannot navigate backwards, and with the back button
    /// hidden there is no UI to trigger one anyway.
    private var path: Binding<[OnboardingStep]> {
        Binding(
            get: {
                switch viewModel.step {
                case .loading, .consent, .completed:
                    return []
                case .hevyKey:
                    return [.hevyKey]
                case .llmKeys:
                    return [.hevyKey, .llmKeys]
                case .trainingProfile:
                    return [.hevyKey, .llmKeys, .trainingProfile]
                }
            },
            set: { _ in }
        )
    }
}

#Preview {
    OnboardingFlowView(viewModel: OnboardingViewModel())
}
