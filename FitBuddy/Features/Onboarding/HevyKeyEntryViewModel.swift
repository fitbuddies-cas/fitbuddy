import Foundation

/// Drives the Hevy API-key entry screen (US-4, step 1): validates the entered
/// key against the Hevy API and persists it to the Keychain only after Hevy
/// accepted it, so no unverified key is ever kept.
@MainActor
final class HevyKeyEntryViewModel: ObservableObject {
    /// Hevy page where the user creates/manages API keys (AC3 error link).
    static let hevyAPISettingsURL = URL(string: "https://hevy.com/settings?developer")!

    /// Raw text field content. Editing after a failure returns to `.idle` so
    /// the error styling clears as soon as the user starts fixing the key.
    @Published var apiKey = "" {
        didSet {
            if case .failed = state, apiKey != oldValue { state = .idle }
        }
    }
    @Published private(set) var state: HevyKeyEntryState = .unknown

    private let validator: HevyKeyValidating
    private let keychain: KeychainService

    init(
        validator: HevyKeyValidating = HevyKeyValidator(),
        keychain: KeychainService = KeychainService()
    ) {
        self.validator = validator
        self.keychain = keychain
    }

    /// Key with surrounding whitespace/newlines removed (pasting often adds a
    /// trailing newline). This is what gets validated and stored.
    var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The connect button is enabled only with non-empty input and no
    /// validation in flight.
    var canConnect: Bool {
        !trimmedKey.isEmpty && state != .validating
    }

    /// Resolves `.unknown` by checking the Keychain: skips the screen when a
    /// (previously validated) key is already stored, e.g. after an app restart
    /// mid-onboarding; otherwise moves to `.idle` for fresh input.
    func bootstrap() async {
        guard state == .unknown else { return }
        do {
            state = try await keychain.exists(.hevyAPIKey) ? .connected : .idle
        } catch {
            // The Keychain can be transiently unreadable (e.g. a prewarm
            // launch while the device is still locked). Fail open to the
            // entry screen rather than spinning forever on .unknown: in the
            // worst case the user re-validates a key that was already stored,
            // and saving simply overwrites it.
            state = .idle
        }
    }

    /// Validates the entered key with a live Hevy API call and stores it in
    /// the Keychain on success. The key is intentionally saved only *after*
    /// HTTP 200 — a rejected key never touches the Keychain.
    func connect() async {
        let key = trimmedKey
        guard !key.isEmpty, state != .validating else { return }

        state = .validating
        do {
            try await validator.validate(key)
        } catch HevyKeyValidationError.invalidKey {
            state = .failed(.invalidKey)
            return
        } catch {
            state = .failed(.network)
            return
        }

        do {
            try await keychain.save(key, for: .hevyAPIKey)
            state = .connected
        } catch {
            state = .failed(.keychain)
        }
    }

    /// Resets a failed attempt back to editing (the "Try again" CTA).
    func retry() {
        if case .failed = state { state = .idle }
    }
}
