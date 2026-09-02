import Foundation

/// Drives the settings screen (#83): manage the stored API keys (replace,
/// delete, add a missing LLM provider), reorder the LLM fallback priority, and
/// wipe all local data.
///
/// Keys are read once per `load()` to build a masked rendering and are never
/// held in plaintext beyond that. Every mutation goes through `KeychainStoring`
/// and `LLMPriorityStore` — nothing here touches `UserDefaults` directly.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var state: SettingsState = .loading

    /// Masked Hevy key, or `nil` when none is stored.
    @Published private(set) var hevyKeyMask: String?
    /// Stored LLM keys in fallback priority order — first is tried first.
    @Published private(set) var llmKeys: [LLMProviderKey] = []

    /// Credential the open editor sheet is editing; `nil` while it is closed.
    @Published var editorTarget: SettingsKeyTarget?
    /// Raw editor input. Editing after a failure returns to `.idle` so the
    /// error styling clears as soon as the user starts fixing the key.
    @Published var editorKey = "" {
        didSet {
            if case .failed = editorState, editorKey != oldValue { editorState = .idle }
        }
    }
    @Published private(set) var editorState: KeyEditorState = .idle

    /// Credential whose delete confirmation is showing; purely presentation
    /// state — the confirmed action carries its own target.
    @Published var pendingDeletion: SettingsKeyTarget?
    /// Whether the "delete all data" confirmation is showing.
    @Published var isConfirmingDeleteAll = false
    @Published private(set) var isDeletingAll = false

    /// Message for an action that failed after the screen was already loaded
    /// (a delete, a reorder). `nil` while the last action succeeded.
    @Published private(set) var actionError: String?

    /// Invoked after the Hevy key was deleted: the session is gone, so the app
    /// has to return to onboarding step 2.
    var onHevyKeyDeleted: (() async -> Void)?
    /// Invoked after all local data was deleted: the app returns to step 1.
    var onDataDeleted: (() -> Void)?
    /// Invoked after a Hevy key was stored — a replacement as well as a first
    /// one. Any cache of a previous key is gone by then, so the dashboard
    /// behind this sheet has to sync again: its own `.task` does not fire when
    /// the sheet is dismissed (#91).
    var onHevyKeyStored: (() -> Void)?

    private let keychain: any KeychainStoring
    private let validator: any HevyKeyValidating
    private let priorityStore: LLMPriorityStore
    private let sessionReset: any SessionResetting
    private let dataReset: any DataResetting

    /// - Parameters:
    ///   - sessionReset: Both Hevy paths go through it — deleting the key
    ///     reuses the US-1 AC3 hard logout, replacing it reuses that logout's
    ///     cache teardown (#91), instead of opening a second teardown path.
    ///   - dataReset: Performs the full local wipe behind "Delete all data".
    init(
        sessionReset: any SessionResetting,
        dataReset: any DataResetting,
        keychain: any KeychainStoring = KeychainService(),
        validator: any HevyKeyValidating = HevyKeyValidator(),
        defaults: UserDefaults = .standard
    ) {
        self.sessionReset = sessionReset
        self.dataReset = dataReset
        self.keychain = keychain
        self.validator = validator
        self.priorityStore = LLMPriorityStore(defaults: defaults)
    }

    // MARK: - Loading

    /// Reads which keys are stored and in which order, masking each one. Safe
    /// to call repeatedly — every mutation ends with a reload.
    func load() async {
        do {
            hevyKeyMask = try await keychain.read(.hevyAPIKey).map(KeyMask.masked)
            llmKeys = try await storedLLMKeys()
            state = .ready
        } catch {
            state = .failed
        }
    }

    /// Providers the user can still add — one slot per provider (#78).
    var addableProviders: [LLMProvider] {
        let stored = Set(llmKeys.map(\.provider))
        return LLMProvider.allCases.filter { !stored.contains($0) }
    }

    /// Stored LLM keys ordered by the persisted priority. A provider whose key
    /// exists without an entry in the order (a partially written order, or one
    /// written by a build that did not know the provider) is appended rather
    /// than hidden — an invisible key is one the user can never delete.
    ///
    /// A repaired order is written back: the list the user sees has to be the
    /// one the fallback chain uses, otherwise an appended key would stay
    /// outside the persisted order and `InferenceService` would never reach it.
    /// The same write prunes providers that the order still names after their
    /// key is gone.
    private func storedLLMKeys() async throws -> [LLMProviderKey] {
        let order = await priorityStore.order
        let ranked = order + LLMProvider.allCases.filter { !order.contains($0) }
        var result: [LLMProviderKey] = []
        for provider in ranked {
            guard let key = try await keychain.read(provider.keychainKey) else { continue }
            result.append(LLMProviderKey(provider: provider, mask: KeyMask.masked(key)))
        }
        let repaired = result.map(\.provider)
        if repaired != order {
            await priorityStore.save(repaired)
        }
        return result
    }

    // MARK: - Key editor

    /// Opens the editor for `target`, always on an empty field: the stored key
    /// is never shown, so it cannot be pre-filled either.
    func beginEditing(_ target: SettingsKeyTarget) {
        editorKey = ""
        editorState = .idle
        editorTarget = target
        actionError = nil
    }

    func cancelEditing() {
        editorTarget = nil
        editorKey = ""
        editorState = .idle
    }

    /// Whether `target` replaces an existing key rather than adding a new one.
    func isReplacing(_ target: SettingsKeyTarget) -> Bool {
        switch target {
        case .hevy:
            return hevyKeyMask != nil
        case .llm(let provider):
            return llmKeys.contains { $0.provider == provider }
        }
    }

    var trimmedEditorKey: String {
        editorKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The save button needs non-empty input and no attempt in flight.
    var canSubmitEditor: Bool {
        !trimmedEditorKey.isEmpty && editorState != .validating
    }

    /// Validates (Hevy only) and stores the entered key, then closes the
    /// editor. A newly added provider joins the priority order last, so an
    /// existing, deliberately chosen order is never reshuffled by an addition.
    /// A stored Hevy key additionally invalidates the workout cache (#91).
    func submitEditor() async {
        guard let target = editorTarget else { return }
        let key = trimmedEditorKey
        guard !key.isEmpty, editorState != .validating else { return }

        editorState = .validating
        if target.isValidatedBeforeSaving {
            do {
                try await validator.validate(key)
            } catch let error as HevyKeyValidationError {
                editorState = .failed(APIKeyEntryFailure(error))
                return
            } catch {
                // The protocol allows arbitrary errors; without an HTTP
                // response a connectivity problem is the closest description.
                editorState = .failed(.network)
                return
            }
        }

        do {
            try await keychain.save(key, for: target.keychainKey)
        } catch {
            editorState = .failed(.keychain)
            return
        }

        switch target {
        case .hevy:
            // The cached workouts belong to the key that was just overwritten.
            // Keeping them would show one Hevy account's training under
            // another's key until the next manual refresh — and feed it to the
            // AI analysis (US-3), which is exactly what the hard logout drops
            // the cache to prevent.
            //
            // Also when the user re-enters the *same* key: telling the two
            // apart would mean reading the stored key back in plaintext to
            // compare it, which this screen deliberately never does. The cost
            // of the safe choice is one re-sync.
            await sessionReset.discardCachedWorkouts()
            onHevyKeyStored?()
        case .llm(let provider):
            if !isReplacing(target) {
                await priorityStore.save(llmKeys.map(\.provider) + [provider])
            }
        }
        cancelEditing()
        await load()
    }

    // MARK: - Priority order

    /// Applies a drag-to-reorder and persists the new fallback priority.
    func moveProviders(fromOffsets source: IndexSet, toOffset destination: Int) async {
        llmKeys.move(fromOffsets: source, toOffset: destination)
        await priorityStore.save(llmKeys.map(\.provider))
    }

    // MARK: - Deletion

    /// Deletes one stored key. The Hevy key takes the hard-logout path (US-1
    /// AC3): it also drops the cached workouts, which would otherwise stay on
    /// the device with no way left to refresh them.
    func delete(_ target: SettingsKeyTarget) async {
        pendingDeletion = nil
        actionError = nil
        switch target {
        case .hevy:
            await sessionReset.hardLogout()
            await onHevyKeyDeleted?()
        case .llm(let provider):
            do {
                try await keychain.delete(provider.keychainKey)
            } catch {
                actionError = "\(provider.displayName)'s key could not be deleted. Please try again."
                return
            }
            // A deleted provider must not linger in the order — the fallback
            // chain would otherwise name a provider with no key.
            await priorityStore.save(llmKeys.map(\.provider).filter { $0 != provider })
            await load()
        }
    }

    /// Wipes every locally stored trace and returns the app to onboarding.
    func deleteAllData() async {
        guard !isDeletingAll else { return }
        isDeletingAll = true
        isConfirmingDeleteAll = false
        await dataReset.deleteAllData()
        isDeletingAll = false
        onDataDeleted?()
    }
}
