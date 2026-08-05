import SwiftUI

/// Root view that gates app access on consent (US-4, step 1), then on the Hevy
/// API key (step 2, #21), then on the optional Claude API key (step 3, #22).
/// Interim wiring: the coordinated 3-step onboarding flow (OnboardingViewModel,
/// #23) replaces the nested switch later.
struct RootView: View {
    @StateObject private var consentViewModel = ConsentViewModel()
    @StateObject private var hevyKeyViewModel = HevyKeyEntryViewModel()
    @StateObject private var claudeKeyViewModel = ClaudeKeyEntryViewModel()

    var body: some View {
        Group {
            switch consentViewModel.state {
            case .unknown:
                loadingView
            case .required:
                ConsentView(viewModel: consentViewModel)
            case .granted:
                switch hevyKeyViewModel.state {
                case .unknown:
                    // Keychain check still running — don't flash the entry
                    // screen at returning users who already stored a key.
                    loadingView
                case .connected:
                    claudeStep
                case .idle, .validating, .failed:
                    HevyKeyEntryView(viewModel: hevyKeyViewModel)
                }
            }
        }
        .task {
            await consentViewModel.bootstrap()
            await hevyKeyViewModel.bootstrap()
            await claudeKeyViewModel.bootstrap()
        }
    }

    @ViewBuilder
    private var claudeStep: some View {
        switch claudeKeyViewModel.state {
        case .unknown:
            // Keychain check still running — don't flash the entry screen at
            // returning users who already stored (or skipped) a key.
            loadingView
        case .saved, .skipped:
            // Dashboard (#27) plugs in here.
            placeholderHome
        case .idle, .saving, .failed:
            ClaudeKeyEntryView(viewModel: claudeKeyViewModel)
        }
    }

    /// Shown while a gate's persisted state is still being read at launch.
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
            Label("Hevy connected", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.fbAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.fbAccentSoft)
                .clipShape(Capsule())
                .padding(.top, 4)
            if claudeKeyViewModel.state == .saved {
                Label("Claude connected", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.fbAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.fbAccentSoft)
                    .clipShape(Capsule())
            } else {
                Label("Claude skipped — AI analysis unavailable", systemImage: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.fbMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.fbCardSubtle)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color.fbBackground)
    }
}

#Preview {
    RootView()
}
