import Foundation

/// Coordinates the 4-step onboarding flow (US-4, US-13): consent (step 1) →
/// Hevy key (step 2) → LLM keys (step 3) → training profile (step 4) →
/// dashboard. Owns the four step view models, resumes at the first incomplete
/// step on launch (app-kill safe), and advances `step` as each child reports
/// completion.
@MainActor
final class OnboardingViewModel: ObservableObject {
    /// DEBUG-only launch argument that bypasses the whole flow, so simulator
    /// demo runs don't need real API keys. Note that no keys exist afterwards
    /// — screens depending on them will show their unavailable/error states.
    static let skipLaunchArgument = "-fbSkipOnboarding"

    // The counterpart to `skipLaunchArgument` for the UI tests (#120) — they
    // need to *walk* the flow rather than skip it — lives in `HevyStubbing`,
    // because the dashboard's sync has to be stubbed by the same decision.

    @Published private(set) var step: OnboardingStep = .loading

    let consentViewModel: ConsentViewModel
    let hevyKeyViewModel: HevyKeyEntryViewModel
    let llmKeysViewModel: LLMKeysViewModel
    let trainingProfileViewModel: TrainingProfileViewModel

    private let keychain: KeychainService
    private let trainingProfileStore: TrainingProfileStore
    private let launchArguments: [String]

    /// The child view models default to sharing this coordinator's Keychain
    /// actor instance; tests inject fully configured children instead.
    init(
        keychain: KeychainService = KeychainService(),
        consentViewModel: ConsentViewModel? = nil,
        hevyKeyViewModel: HevyKeyEntryViewModel? = nil,
        llmKeysViewModel: LLMKeysViewModel? = nil,
        trainingProfileViewModel: TrainingProfileViewModel? = nil,
        trainingProfileStore: TrainingProfileStore = TrainingProfileStore(),
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.trainingProfileStore = trainingProfileStore
        self.keychain = keychain
        self.launchArguments = launchArguments
        self.consentViewModel = consentViewModel ?? ConsentViewModel(keychain: keychain)
        self.hevyKeyViewModel = hevyKeyViewModel
            ?? HevyKeyEntryViewModel(
                validator: Self.validator(for: launchArguments),
                keychain: keychain
            )
        self.llmKeysViewModel = llmKeysViewModel ?? LLMKeysViewModel(keychain: keychain)
        self.trainingProfileViewModel = trainingProfileViewModel
            ?? TrainingProfileViewModel(store: trainingProfileStore)

        self.consentViewModel.onGranted = { [weak self] in self?.step = self?.resolvedStep ?? .hevyKey }
        self.hevyKeyViewModel.onConnected = { [weak self] in self?.step = self?.resolvedStep ?? .llmKeys }
        self.llmKeysViewModel.onFinished = { [weak self] in
            self?.step = self?.resolvedStep ?? .trainingProfile
        }
        self.trainingProfileViewModel.onFinished = { [weak self] in self?.step = .completed }
    }

    /// Resolves `.loading` by bootstrapping all four children, then resuming
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
        await trainingProfileViewModel.bootstrap()
        await excuseInstallsThatPredateTheProfileStep()
        step = resolvedStep
    }

    /// Marks step 4 as settled for an install that finished onboarding before
    /// the step existed (US-13, #190).
    ///
    /// Without this, `resolvedStep` would send every existing user back into
    /// onboarding for a question the app never asked them — the decision on
    /// #189 is that they reach it through Settings instead.
    ///
    /// The discriminator is the *first* bootstrap after this version arrives.
    /// A fresh install has nothing finished at that moment, so it is not
    /// excused and walks all four steps; an install that already holds a Hevy
    /// key and an LLM decision then was complete under the old three, and is.
    /// Checking "is complete" alone would also excuse a new user who quit
    /// right after step 3 and came back — they would silently never be asked.
    private func excuseInstallsThatPredateTheProfileStep() async {
        guard await !trainingProfileStore.hasSeenIntroduction else { return }
        await trainingProfileStore.markIntroductionSeen()
        guard completedTheFirstThreeSteps else { return }
        await trainingProfileStore.setSkipped()
        trainingProfileViewModel.reset()
        await trainingProfileViewModel.bootstrap()
    }

    /// Whether the Hevy key and the LLM decision are both settled — onboarding
    /// as it stood before US-13.
    ///
    /// Consent is deliberately not part of it. A consent bump makes step 1
    /// `.required` again on the very launch this check runs, and an install
    /// that came through the old three steps would then not be excused — but
    /// the marker is written regardless, so after the re-consent every
    /// existing user would land in step 4 (#195 review). The key and the
    /// decision alone prove the previous install: a fresh one has neither at
    /// its first bootstrap, because `FirstLaunchResetService` purged the
    /// Keychain and the defaults are empty.
    private var completedTheFirstThreeSteps: Bool {
        guard hevyKeyViewModel.state == .connected else { return false }
        switch llmKeysViewModel.state {
        case .saved, .skipped: return true
        case .unknown, .idle, .saving, .failed: return false
        }
    }

    /// Entry point for an HTTP 401 from Hevy anywhere in the app: the stored
    /// key is no longer valid, so it is removed and the flow returns to step 2
    /// for a fresh one. Future services (e.g. WorkoutSyncService, #25) reach this via
    /// the coordinator `RootView` injects into the environment.
    ///
    /// Announces itself on arrival (US-8 AC2). The user did not ask for this
    /// screen and never saw the 401, so without the notice they are moved out
    /// of a working dashboard for no stated reason — the silent failure the AC
    /// rules out, in a different form than carrying on with cached data.
    func handleHevyUnauthorized() async {
        await returnToHevyStep(announcing: .keyRejected)
    }

    /// Entry point for the user deleting the Hevy key in Settings (#83). Same
    /// route back to step 2 and no notice: they are standing on the screen
    /// that sent them, so there is nothing to explain.
    func handleHevyKeyDeleted() async {
        await returnToHevyStep(announcing: nil)
    }

    private func returnToHevyStep(announcing notice: HevyKeyEntryNotice?) async {
        // A failed delete is tolerable: the flow still returns to step 2, and
        // saving a freshly validated key simply overwrites the stale one.
        try? await keychain.delete(.hevyAPIKey)
        hevyKeyViewModel.reset(announcing: notice)
        step = .hevyKey
    }

    /// Entry point for "Delete all data" in Settings (#83). `DataResetService`
    /// has already wiped every persisted trace, so the children are returned
    /// to their fresh-install state and the flow restarts at step 1 — consent
    /// has to be given again (US-4 AC5).
    func handleDataReset() {
        consentViewModel.reset()
        hevyKeyViewModel.reset()
        llmKeysViewModel.reset()
        trainingProfileViewModel.reset()
        step = .consent
    }

    /// The key validator for this launch: the live one, unless a UI test asked
    /// for a fixed verdict (#120).
    private static func validator(for launchArguments: [String]) -> any HevyKeyValidating {
        #if DEBUG
        if let verdict = HevyStubbing.verdict(in: launchArguments) {
            return StubHevyKeyValidator(verdict: verdict)
        }
        #endif
        return HevyKeyValidator()
    }

    /// First incomplete step according to the children's persisted state.
    /// The LLM step counts as complete on an explicit decision only (saved
    /// keys or persisted skip) — a user killed mid-step-3 resumes there, not
    /// on the dashboard.
    private var resolvedStep: OnboardingStep {
        guard consentViewModel.state == .granted else { return .consent }
        guard hevyKeyViewModel.state == .connected else { return .hevyKey }
        switch llmKeysViewModel.state {
        case .unknown, .idle, .saving, .failed:
            return .llmKeys
        case .saved, .skipped:
            break
        }
        switch trainingProfileViewModel.state {
        case .saved, .skipped:
            return .completed
        case .unknown, .idle:
            return .trainingProfile
        }
    }
}
