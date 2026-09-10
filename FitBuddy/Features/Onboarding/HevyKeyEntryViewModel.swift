import Foundation

/// Drives the Hevy API-key entry screen (US-4, step 2): validates the entered
/// key against the Hevy API and persists it to the Keychain only after Hevy
/// accepted it, so no unverified key is ever kept.
@MainActor
final class HevyKeyEntryViewModel: ObservableObject {
    /// Raw text field content. Editing after a failure returns to `.idle` so
    /// the error styling clears as soon as the user starts fixing the key.
    @Published var apiKey = "" {
        didSet {
            if case .failed = state, apiKey != oldValue { state = .idle }
        }
    }
    @Published private(set) var state: HevyKeyEntryState = .unknown
    /// Why the app sent the user here, when it was not their own doing — the
    /// banner above the form (US-8 AC2). `nil` for every screen the user
    /// walked into themselves.
    @Published private(set) var notice: HevyKeyEntryNotice?

    /// Invoked when a key was actively validated and stored (not on a
    /// bootstrap restore) — lets the onboarding coordinator advance to step 3.
    var onConnected: (() -> Void)?

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
        } catch let error as HevyKeyValidationError {
            state = .failed(APIKeyEntryFailure(error))
            return
        } catch {
            // The protocol allows arbitrary errors; without an HTTP response
            // a connectivity problem is the closest description.
            state = .failed(.network)
            return
        }

        do {
            try await keychain.save(key, for: .hevyAPIKey)
            state = .connected
            // The reason the user was sent here is spent: a key Hevy just
            // accepted is the answer to it, and leaving the banner up would
            // keep announcing a problem that no longer exists.
            notice = nil
            onConnected?()
        } catch {
            state = .failed(.keychain)
        }
    }

    /// Returns to fresh input after the stored key went away — an HTTP 401
    /// anywhere in the app, or the user deleting it in Settings. Clears the
    /// field so the old key cannot be resubmitted by accident.
    ///
    /// - Parameter notice: What to tell the user about why they are here.
    ///   Defaults to nothing, which is right for every reset the user asked
    ///   for; the revoked-key path passes `.keyRejected` (US-8 AC2).
    func reset(announcing notice: HevyKeyEntryNotice? = nil) {
        apiKey = ""
        state = .idle
        // After `apiKey`, whose `didSet` does not touch this but would make the
        // ordering load-bearing if it ever did.
        self.notice = notice
    }

    /// Resets a failed attempt back to editing (the "Try again" CTA).
    func retry() {
        if case .failed = state { state = .idle }
    }
}
