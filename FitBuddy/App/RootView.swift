import SwiftUI

/// Root view that gates app access on consent (US-4), then on the Hevy API key
/// (step 1, #21). Interim wiring: the coordinated 3-step onboarding flow
/// (OnboardingViewModel, #23) replaces the nested switch later.
struct RootView: View {
    @StateObject private var consentViewModel = ConsentViewModel()
    @StateObject private var hevyKeyViewModel = HevyKeyEntryViewModel()

    var body: some View {
        Group {
            switch consentViewModel.state {
            case .unknown:
                FBSpinner()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.fbBackground)
            case .required:
                ConsentView(viewModel: consentViewModel)
            case .granted:
                if hevyKeyViewModel.state == .connected {
                    // Step 2 (Claude key, #22) plugs in here.
                    placeholderHome
                } else {
                    HevyKeyEntryView(viewModel: hevyKeyViewModel)
                }
            }
        }
        .task {
            await consentViewModel.bootstrap()
            await hevyKeyViewModel.bootstrap()
        }
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
            // Interim confirmation that step 1 succeeded, until the Claude key
            // screen (#22) and dashboard (#27) take over from here.
            Label("Hevy connected", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.fbAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.fbAccentSoft)
                .clipShape(Capsule())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color.fbBackground)
    }
}

#Preview {
    RootView()
}
