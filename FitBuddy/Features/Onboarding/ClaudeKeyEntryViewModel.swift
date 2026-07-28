import Foundation

/// Drives the Claude API-key entry screen (US-4, step 3): persists the entered
/// key to the Keychain, or lets the user skip the step entirely (AC2). There is
/// no live validation against the Claude API — a rejected key just fails later,
/// at the point of the first AI analysis call (US-3).
@MainActor
final class ClaudeKeyEntryViewModel: ObservableObject {
    /// Anthropic console page where the user creates/manages API keys.
    static let anthropicConsoleURL = URL(staticString: "https://console.anthropic.com/settings/keys")

    /// Raw text field content. Editing after a failure returns to `.idle` so
    /// the error styling clears as soon as the user starts fixing the key.
    @Published var apiKey = "" {
        didSet {
            if case .failed = state, apiKey != oldValue { state = .idle }
        }
    }
    @Published private(set) var state: ClaudeKeyEntryState = .unknown

    private let keychain: KeychainService

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
    }

    /// Key with surrounding whitespace/newlines removed (pasting often adds a
    /// trailing newline). This is what gets stored.
    var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The save button is enabled only with non-empty input and no save in
    /// flight.
    var canSave: Bool {
        !trimmedKey.isEmpty && state != .saving
    }

    /// Resolves `.unknown` by checking the Keychain: skips the screen when a
    /// key is already stored, e.g. after an app restart mid-onboarding;
    /// otherwise moves to `.idle` for fresh input.
    func bootstrap() async {
        guard state == .unknown else { return }
        do {
            state = try await keychain.exists(.claudeAPIKey) ? .saved : .idle
        } catch {
            // Fail open to the entry screen rather than spinning forever on
            // .unknown — see HevyKeyEntryViewModel.bootstrap() for the same
            // reasoning.
            state = .idle
        }
    }

    /// Persists the entered key to the Keychain. No-op on empty input.
    func save() async {
        let key = trimmedKey
        guard !key.isEmpty, state != .saving else { return }

        state = .saving
        do {
            try await keychain.save(key, for: .claudeAPIKey)
            state = .saved
        } catch {
            state = .failed(.keychain)
        }
    }

    /// Continues onboarding without a Claude key (AC2 "Überspringen").
    func skip() {
        state = .skipped
    }

    /// Resets a failed attempt back to editing (the "Try again" CTA).
    func retry() {
        if case .failed = state { state = .idle }
    }
}
