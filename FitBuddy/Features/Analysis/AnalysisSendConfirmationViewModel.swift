import Foundation
import OSLog

/// Drives the confirmation sheet that stands between "Analyze with AI" and
/// the first byte leaving the device (US-3 AC12, #268): which providers will
/// receive the data, whether the user has ticked the box, and the proof of
/// that tick once they have.
///
/// One instance per opening of the sheet — `AnalysisViewModel.requestStart()`
/// builds a fresh one every time, which is what keeps the checkbox empty on
/// every opening. There is deliberately no "don't ask again": the provider
/// list can change between two runs (a key added or removed in Settings),
/// and a confirmation covers exactly the list it was shown with. Asking once
/// per run is the only way the stored proof and the actual recipients can
/// never disagree.
@MainActor
final class AnalysisSendConfirmationViewModel: ObservableObject, Identifiable {
    /// What a run sends, as the sheet lists it — the categories, not the
    /// values. Kept here rather than in the view so the sheet and its tests
    /// read the same list.
    static let sentDataCategories: [String] = [
        "Date and duration of your workouts over the last 8 weeks",
        "Exercises with sets, repetitions and weights",
        "Heart-rate and cardio figures from Strava or Polar, if connected",
        "Your training profile: goal and years of experience, if set",
    ]

    /// What a run never sends. Named explicitly: "training data" alone
    /// leaves the user guessing whether their account travels with it.
    static let notSentNote = "Not sent: your name, e-mail address or any account ID."

    /// Whether the user ticked "I understand …". Starts unticked on every
    /// instance — see the type comment.
    @Published var hasConfirmedCheckbox = false
    /// The recipients in fallback order: every provider with a stored key,
    /// first to be asked first. Empty until `load()` has read the Keychain,
    /// and empty when no key is stored.
    @Published private(set) var providers: [LLMProvider] = []
    /// `true` while `load()` reads the priority order and the Keychain.
    @Published private(set) var isLoadingProviders = false
    /// `true` when the Keychain could not be read — a locked device, most
    /// likely. The list is then unknown, and a confirmation of an unknown
    /// list is not a confirmation, so the sheet says so and cannot send.
    @Published private(set) var couldNotReadProviders = false

    /// Whether "Send & analyze" is enabled: the box is ticked, the list is
    /// in, and it is one the user could actually read.
    var canSend: Bool {
        hasConfirmedCheckbox && !isLoadingProviders && !couldNotReadProviders
    }

    private let keychain: any KeychainStoring
    private let priority: LLMPriorityStore
    private let consentVersion: String
    private let now: () -> Date

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "AnalysisSendConfirmation")

    /// - Parameters:
    ///   - keychain: Where the provider keys live; only `read` is used, and
    ///     only to tell a configured provider from an unconfigured one.
    ///   - priority: The fallback order the user set (US-4).
    ///   - consentVersion: The onboarding consent version this confirmation
    ///     sits on top of — `ConsentViewModel.currentVersion` in the app,
    ///     injectable so a test does not depend on the date in that constant.
    ///   - now: Injectable clock for the confirmation timestamp.
    init(
        keychain: any KeychainStoring = KeychainService(),
        priority: LLMPriorityStore = LLMPriorityStore(),
        consentVersion: String = ConsentViewModel.currentVersion,
        now: @escaping () -> Date = Date.init
    ) {
        self.keychain = keychain
        self.priority = priority
        self.consentVersion = consentVersion
        self.now = now
    }

    /// Resolves the recipient list — the sheet's `.task`.
    ///
    /// The same walk as `InferenceService.resolveCandidates()`: the stored
    /// order, then every provider it does not name, keeping those with a
    /// non-empty key. A provider without a key is left out rather than shown
    /// greyed: it receives nothing, so it is not a recipient.
    func load() async {
        isLoadingProviders = true
        defer { isLoadingProviders = false }
        couldNotReadProviders = false
        let order = LLMProvider.fallbackOrder(from: await priority.order)
        var configured: [LLMProvider] = []
        for provider in order {
            let stored: String?
            do {
                stored = try await keychain.read(provider.keychainKey)
            } catch {
                // Not "no key": the key may well be there and unreadable
                // right now. Listing fewer recipients than the run would use
                // is the one thing this sheet must never do.
                logger.error("Provider keys not readable for the confirmation sheet: \(error, privacy: .public)")
                couldNotReadProviders = true
                providers = []
                return
            }
            guard let key = stored, !key.isEmpty else { continue }
            configured.append(provider)
        }
        providers = configured
    }

    /// The proof of the user's go-ahead, or `nil` when they have not given
    /// it — the box is unticked, or the list could not be read. What
    /// `AnalysisViewModel.confirmSend()` hands to the run and stores with
    /// its result.
    func confirm() -> AnalysisSendConfirmation? {
        guard canSend else { return nil }
        return AnalysisSendConfirmation(
            confirmedAt: now(),
            consentVersion: consentVersion,
            providers: providers
        )
    }
}
