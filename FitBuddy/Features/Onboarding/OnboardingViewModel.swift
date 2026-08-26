import Foundation

/// Coordinates the 3-step onboarding flow (US-4): consent (step 1) → Hevy key
/// (step 2) → LLM keys (step 3) → dashboard. Owns the three step view models,
/// resumes at the first incomplete step on launch (app-kill safe), and advances
/// `step` as each child reports completion.
@MainActor
final class OnboardingViewModel: ObservableObject {
    /// DEBUG-only launch argument that bypasses the whole flow, so simulator
    /// demo runs and future UI tests don't need real API keys. Note that no
    /// keys exist afterwards — screens depending on them will show their
    /// unavailable/error states.
    static let skipLaunchArgument = "-fbSkipOnboarding"

    @Published private(set) var step: OnboardingStep = .loading

    let consentViewModel: ConsentViewModel
    let hevyKeyViewModel: HevyKeyEntryViewModel
    let llmKeysViewModel: LLMKeysViewModel

    private let keychain: KeychainService
    private let launchArguments: [String]

    /// The child view models default to sharing this coordinator's Keychain
    /// actor instance; tests inject fully configured children instead.
    init(
        keychain: KeychainService = KeychainService(),
        consentViewModel: ConsentViewModel? = nil,
        hevyKeyViewModel: HevyKeyEntryViewModel? = nil,
        llmKeysViewModel: LLMKeysViewModel? = nil,
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.keychain = keychain
        self.launchArguments = launchArguments
        self.consentViewModel = consentViewModel ?? ConsentViewModel(keychain: keychain)
        self.hevyKeyViewModel = hevyKeyViewModel ?? HevyKeyEntryViewModel(keychain: keychain)
        self.llmKeysViewModel = llmKeysViewModel ?? LLMKeysViewModel(keychain: keychain)

        self.consentViewModel.onGranted = { [weak self] in self?.step = self?.resolvedStep ?? .hevyKey }
        self.hevyKeyViewModel.onConnected = { [weak self] in self?.step = self?.resolvedStep ?? .llmKeys }
        self.llmKeysViewModel.onFinished = { [weak self] in self?.step = .completed }
    }

    /// Resolves `.loading` by bootstrapping all three children, then resuming
    /// at the first incomplete step — after an app kill the user returns to
    /// exactly where they left off. No-op once resolved.
    func bootstrap() async {
        guard step == .loading else { return }
        #if DEBUG
        if launchArguments.contains(Self.skipLaunchArgument) {
            step = .completed
            return
        }
        #endif
        await consentViewModel.bootstrap()
        await hevyKeyViewModel.bootstrap()
        await llmKeysViewModel.bootstrap()
        step = resolvedStep
    }

    /// Entry point for an HTTP 401 from Hevy anywhere in the app: the stored
    /// key is no longer valid, so it is removed and the flow returns to step 2
    /// for a fresh one. Future services (e.g. HevyService, #25) reach this via
    /// the coordinator `RootView` injects into the environment.
    func handleHevyUnauthorized() async {
        // A failed delete is tolerable: the flow still returns to step 2, and
        // saving a freshly validated key simply overwrites the stale one.
        try? await keychain.delete(.hevyAPIKey)
        hevyKeyViewModel.reset()
        step = .hevyKey
    }

    /// First incomplete step according to the children's persisted state.
    /// The LLM step counts as complete on an explicit decision only (saved
    /// keys or persisted skip) — a user killed mid-step-3 resumes there, not
    /// on the dashboard.
    private var resolvedStep: OnboardingStep {
        guard consentViewModel.state == .granted else { return .consent }
        guard hevyKeyViewModel.state == .connected else { return .hevyKey }
        switch llmKeysViewModel.state {
        case .saved, .skipped:
            return .completed
        case .unknown, .idle, .saving, .failed:
            return .llmKeys
        }
    }
}
