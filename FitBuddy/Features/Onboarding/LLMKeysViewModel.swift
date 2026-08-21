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

    private let keychain: KeychainService
    private let priorityStore: LLMPriorityStore
    private let defaults: UserDefaults

    init(keychain: KeychainService = KeychainService(), defaults: UserDefaults = .standard) {
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

    /// The save button needs at least one complete slot and no save in
    /// flight. Incomplete slots are ignored on save rather than blocking it.
    var canSave: Bool {
        slots.contains(where: \.isComplete) && state != .saving
    }

    /// Persists every complete slot's key to the Keychain and the slot order
    /// as the provider priority. No-op without a complete slot.
    func save() async {
        let completeSlots = slots.filter(\.isComplete)
        guard !completeSlots.isEmpty, state != .saving else { return }

        state = .saving
        do {
            for slot in completeSlots {
                guard let provider = slot.provider else { continue }
                try await keychain.save(slot.trimmedKey, for: provider.keychainKey)
            }
            priorityStore.save(completeSlots.compactMap(\.provider))
            state = .saved
            onFinished?()
        } catch {
            state = .failed(.keychain)
        }
    }

    /// Continues onboarding without any LLM key (AC2 "Überspringen").
    /// Persisted via `UserDefaults` so the entry screen doesn't reappear on
    /// every cold start until the user actually adds a key.
    func skip() {
        defaults.set(true, forKey: Self.skippedKey)
        state = .skipped
        onFinished?()
    }

    /// Resolves `.unknown` by checking the Keychain: skips the screen when at
    /// least one provider key is already stored, e.g. after an app restart
    /// mid-onboarding; otherwise moves to `.idle` for fresh input.
    func bootstrap() async {
        guard state == .unknown else { return }
        do {
            for provider in LLMProvider.allCases {
                if try await keychain.exists(provider.keychainKey) {
                    state = .saved
                    return
                }
            }
            state = defaults.bool(forKey: Self.skippedKey) ? .skipped : .idle
        } catch {
            // Fail open rather than spinning forever on .unknown — but honor a
            // previously persisted skip: it lives in UserDefaults and is
            // unaffected by the Keychain failure.
            state = defaults.bool(forKey: Self.skippedKey) ? .skipped : .idle
        }
    }
}
