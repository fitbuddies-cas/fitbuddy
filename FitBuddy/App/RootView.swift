import SwiftUI

/// Root view gating app access on the 3-step onboarding flow (US-4), which is
/// coordinated by `OnboardingViewModel`: consent → Hevy key → Claude key →
/// dashboard (placeholder until #27).
struct RootView: View {
    @StateObject private var onboardingViewModel = OnboardingViewModel()

    var body: some View {
        Group {
            switch onboardingViewModel.step {
            case .loading:
                loadingView
            case .consent, .hevyKey, .claudeKey:
                OnboardingFlowView(viewModel: onboardingViewModel)
            case .completed:
                placeholderHome
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

    /// Stand-in for the post-onboarding app surface (Dashboard arrives in #27).
    private var placeholderHome: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.fbAccent)
            Text("FitBuddy")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.fbInk)
            Text("PoC skeleton – ready for Sprint 1")
                .font(.subheadline)
                .foregroundStyle(Color.fbInkSecondary)
            // Interim confirmation of onboarding status, until the dashboard
            // (#27) takes over from here.
            statusBadge("Hevy connected", icon: "checkmark.circle.fill", emphasized: true)
                .padding(.top, 4)
            if onboardingViewModel.claudeKeyViewModel.state == .saved {
                statusBadge("Claude connected", icon: "checkmark.circle.fill", emphasized: true)
            } else {
                statusBadge("Claude skipped — AI analysis unavailable", icon: "info.circle", emphasized: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color.fbBackground)
    }

    private func statusBadge(_ text: String, icon: String, emphasized: Bool) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(emphasized ? Color.fbAccent : Color.fbMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(emphasized ? Color.fbAccentSoft : Color.fbCardSubtle)
            .clipShape(Capsule())
    }
}

#Preview {
    RootView()
}
