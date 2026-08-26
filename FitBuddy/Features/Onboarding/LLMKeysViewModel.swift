import Foundation

/// Drives the LLM API-key entry screen (US-4, step 3): up to three
/// provider/key slots (Claude, Gemini, Mistral) whose order is the fallback
/// priority for analysis calls. Keys are persisted to the Keychain, the order
/// to `LLMPriorityStore`, or the user skips the step entirely (AC2). There is
/// no live validation against the provider APIs — a rejected key just fails
/// later, at the point of the first AI analysis call (US-3).
@MainActor
final class LLMKeysViewModel: ObservableObject {
    /// Maximum number of provider slots — one per supported provider.
    static let maxSlots = LLMProvider.allCases.count

    /// Provider/key slots in priority order. Editing after a failure returns
    /// to `.idle` so the error styling clears as soon as the user starts
    /// fixing the input.
    @Published var slots: [LLMKeySlot] = [LLMKeySlot()] {
        didSet {
            if case .failed = state, slots != oldValue { state = .idle }
        }
    }
    @Published private(set) var state: LLMKeysState = .unknown

    /// Invoked on an active step-3 decision — keys saved or step skipped (not
    /// on a bootstrap restore) — letting the coordinator finish onboarding.
    var onFinished: (() -> Void)?

    /// `UserDefaults` key backing the "skip for now" decision (AC2). Unlike the
    /// Keychain, `UserDefaults` is wiped on app deletion, so a skip does not
    /// outlive a reinstall — see `FirstLaunchResetService` for the same
    /// reasoning applied to its own marker.
    private static let skippedKey = "fitbuddy.onboarding.llmKeysSkipped"

    /// Name this marker had while step 3 took a single Claude key. Existing
    /// testers who skipped back then still carry it, so it is read as a
    /// fallback and migrated forward once — without it, their decision would be
    /// lost on update and step 3 would reappear.
    private static let legacySkippedKey = "fitbuddy.onboarding.claudeKeySkipped"

    private let keychain: any KeychainStoring
    private let priorityStore: LLMPriorityStore
    private let defaults: UserDefaults

    init(keychain: any KeychainStoring = KeychainService(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        self.priorityStore = LLMPriorityStore(defaults: defaults)
    }

    /// Providers still selectable for the given slot: all that are not taken
    /// by another slot. The slot's own choice stays selectable.
    func availableProviders(for slot: LLMKeySlot) -> [LLMProvider] {
        let taken = Set(slots.filter { $0.id != slot.id }.compactMap(\.provider))
        return LLMProvider.allCases.filter { !taken.contains($0) }
    }

    /// Assigns a provider to a slot. Changing an existing choice clears the
    /// slot's key — a key never silently carries over to another provider.
    func select(_ provider: LLMProvider, forSlot id: LLMKeySlot.ID) {
        guard let index = slots.firstIndex(where: { $0.id == id }),
              slots[index].provider != provider else { return }
        slots[index].provider = provider
        slots[index].key = ""
    }

    /// A further slot can be added once every existing one is complete, up to
    /// one slot per provider.
    var canAddSlot: Bool {
        slots.count < Self.maxSlots && slots.allSatisfy(\.isComplete) && state != .saving
    }

    func addSlot() {
        guard canAddSlot else { return }
        slots.append(LLMKeySlot())
    }

    /// Removes a slot, the only way to undo a provider choice. The screen
    /// always keeps at least one picker, so removing the last remaining slot
    /// empties it instead of leaving the user with nothing to fill in.
    func removeSlot(_ id: LLMKeySlot.ID) {
        guard state != .saving, let index = slots.firstIndex(where: { $0.id == id }) else { return }
        if slots.count == 1 {
            slots[0] = LLMKeySlot()
        } else {
            slots.remove(at: index)
        }
    }

    /// A slot the user started but did not finish: a provider is picked, the
    /// key is still missing. Saving would drop that choice silently, so it
    /// blocks the save until the user fills the key in or removes the slot.
    var hasPartialSlot: Bool {
        slots.contains { $0.provider != nil && !$0.isComplete }
    }

    /// The save button needs at least one complete slot, no half-filled slot
    /// that would be dropped silently, and no save in flight.
    var canSave: Bool {
        slots.contains(where: \.isComplete) && !hasPartialSlot && state != .saving
    }

    /// Persists every complete slot's key to the Keychain and the slot order
    /// as the provider priority. No-op without a complete slot.
    ///
    /// The Keychain writes are sequential, so a failure halfway through would
    /// leave keys behind that no priority order references — orphans the user
    /// can no longer see or remove once they skip the step. The already
    /// written keys are therefore rolled back before reporting the failure,
    /// leaving keys and priority order consistent: either all of them or none.
    func save() async {
        // `canSave` rather than a local check: the key field's `onSubmit`
        // reaches this directly, bypassing the disabled save button.
        guard canSave else { return }
        let completeSlots = slots.filter(\.isComplete)

        state = .saving
        var written: [LLMProvider] = []
        do {
            for slot in completeSlots {
                guard let provider = slot.provider else { continue }
                try await keychain.save(slot.trimmedKey, for: provider.keychainKey)
                written.append(provider)
            }
            await priorityStore.save(completeSlots.compactMap(\.provider))
            state = .saved
            onFinished?()
        } catch {
            // Best effort: a delete that fails too leaves the Keychain as it
            // was, which is no worse than not trying.
            for provider in written {
                try? await keychain.delete(provider.keychainKey)
            }
            state = .failed(.keychain)
        }
    }

    /// Continues onboarding without any LLM key (AC2 "Überspringen").
    /// Persisted via `UserDefaults` so the entry screen doesn't reappear on
    /// every cold start until the user actually adds a key.
    func skip() {
        defaults.set(true, forKey: Self.skippedKey)
        defaults.removeObject(forKey: Self.legacySkippedKey)
        state = .skipped
        onFinished?()
    }

    /// Whether the user already declined the step, honoring the pre-multi-provider
    /// marker and migrating it forward so the stale entry does not linger.
    private var hasSkipped: Bool {
        if defaults.bool(forKey: Self.skippedKey) { return true }
        guard defaults.bool(forKey: Self.legacySkippedKey) else { return false }
        defaults.set(true, forKey: Self.skippedKey)
        defaults.removeObject(forKey: Self.legacySkippedKey)
        return true
    }

    /// Resolves `.unknown` by checking the Keychain: skips the screen when at
    /// least one provider key is already stored, e.g. after an app restart
    /// mid-onboarding; otherwise moves to `.idle` for fresh input.
    func bootstrap() async {
        guard state == .unknown else { return }
        let keychain = self.keychain
        // Concurrently, and each provider on its own `try?`: a throwing read
        // (e.g. `errSecInteractionNotAllowed` on a locked device during a
        // background launch) must not mask the providers that would have
        // answered, and three serial round-trips sit on the launch critical
        // path — `OnboardingViewModel.bootstrap()` awaits this before the root
        // view can leave `.loading`.
        let hasStoredKey = await withTaskGroup(of: Bool.self) { group in
            for provider in LLMProvider.allCases {
                group.addTask {
                    (try? await keychain.exists(provider.keychainKey)) ?? false
                }
            }
            return await group.reduce(false) { $0 || $1 }
        }
        // Fail open rather than spinning forever on `.unknown`: with every read
        // failing this lands on `.idle`, or on `.skipped` when the user already
        // declined — that marker lives in UserDefaults and is unaffected.
        state = hasStoredKey ? .saved : (hasSkipped ? .skipped : .idle)
    }
}
