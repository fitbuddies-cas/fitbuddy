import SwiftUI

/// Root view that gates app access on consent (US-4). Until consent for the
/// current version is stored, the consent screen is shown; afterwards the app
/// content follows. The full onboarding (API keys, #21–24) plugs in here later.
struct RootView: View {
    @StateObject private var consentViewModel = ConsentViewModel()

    var body: some View {
        Group {
            switch consentViewModel.state {
            case .unknown:
                ProgressView()
            case .required:
                ConsentView(viewModel: consentViewModel)
            case .granted:
                placeholderHome
            }
        }
        .task { await consentViewModel.bootstrap() }
    }

    /// Stand-in for the post-onboarding app surface (Dashboard arrives in #27).
    private var placeholderHome: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("FitBuddy")
                .font(.largeTitle.bold())
            Text("PoC-Skelett – bereit für Sprint 1")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
