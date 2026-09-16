import Foundation

/// Drives the Polar application-credentials screen (ADR-11, mirrors
/// `StravaCredentialsViewModel`): takes the client ID and client secret of the
/// user's own Polar AccessLink application and stores them in the Keychain.
///
/// Nothing is verified here — see `PolarCredentialsState`. What the screen
/// *can* do is show whether a pair is already stored, so the user knows
/// whether saving replaces something.
@MainActor
final class PolarCredentialsViewModel: ObservableObject {
    /// Raw field contents. Editing after a failure returns to `.idle` so the
    /// error styling clears as soon as the user starts fixing the input.
    @Published var clientID = "" {
        didSet { clearFailure(if: clientID != oldValue) }
    }
    @Published var clientSecret = "" {
        didSet { clearFailure(if: clientSecret != oldValue) }
    }
    @Published private(set) var state: PolarCredentialsState = .unknown

    /// Client ID of the pair stored when the screen opened, or `nil`. Not a
    /// secret — it travels in the browser URL — so it can be shown in full.
    @Published private(set) var storedClientID: String?
    /// Masked secret of that same pair, or `nil`. Never the plaintext.
    @Published private(set) var storedSecretMask: String?

    /// Invoked after a pair was stored. The connection screen uses it to
    /// re-check whether "Connect" can be enabled.
    var onSaved: (() -> Void)?

    private let store: any PolarCredentialStoring

    init(store: any PolarCredentialStoring = PolarCredentialStore()) {
        self.store = store
    }

    // MARK: - Input

    /// Pasting often adds a trailing newline; both values are stored trimmed.
    var trimmedClientID: String {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedClientSecret: String {
        clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Save needs both fields and no write in flight.
    var canSave: Bool {
        !trimmedClientID.isEmpty && !trimmedClientSecret.isEmpty && state != .saving
    }

    /// Whether a pair is already stored, i.e. saving replaces it.
    var hasStoredCredentials: Bool {
        storedClientID != nil
    }

    // MARK: - Lifecycle

    /// Resolves `.unknown` by reading what is stored. The fields stay empty
    /// either way — the stored secret is never displayed, so it cannot be
    /// pre-filled either.
    func bootstrap() async {
        guard state == .unknown else { return }
        do {
            if let stored = try await store.clientCredentials() {
                storedClientID = stored.clientID
                storedSecretMask = KeyMask.masked(stored.clientSecret)
            }
        } catch {
            // A transiently unreadable Keychain (prewarm launch while still
            // locked) should not block entry. Worst case the user re-enters a
            // pair that was already there, and saving overwrites it.
        }
        state = .idle
    }

    /// Stores the trimmed pair. On a Keychain failure the input is kept so the
    /// user can simply retry.
    func save() async {
        // `canSave` rather than a local check: the field's `onSubmit` reaches
        // this directly, bypassing the disabled save button.
        guard canSave else { return }

        let credentials = PolarClientCredentials(
            clientID: trimmedClientID,
            clientSecret: trimmedClientSecret
        )
        state = .saving
        do {
            try await store.saveClientCredentials(credentials)
            storedClientID = credentials.clientID
            storedSecretMask = KeyMask.masked(credentials.clientSecret)
            state = .saved
            onSaved?()
        } catch {
            state = .failed(.keychain)
        }
    }

    /// Back to fresh input, e.g. after a disconnect wiped the pair.
    func reset() {
        clientID = ""
        clientSecret = ""
        storedClientID = nil
        storedSecretMask = nil
        state = .idle
    }

    private func clearFailure(if changed: Bool) {
        if case .failed = state, changed { state = .idle }
    }
}
