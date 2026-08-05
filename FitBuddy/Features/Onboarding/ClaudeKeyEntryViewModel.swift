import Foundation

/// Drives the Claude API-key entry screen (US-4, step 2): persists the entered
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

    /// `UserDefaults` key backing the "skip for now" decision (AC2). Unlike the
    /// Keychain, `UserDefaults` is wiped on app deletion, so a skip does not
    /// outlive a reinstall — see `FirstLaunchResetService` for the same
    /// reasoning applied to its own marker.
    private static let skippedKey = "fitbuddy.onboarding.claudeKeySkipped"

    private let keychain: KeychainService
    private let defaults: UserDefaults

    init(keychain: KeychainService = KeychainService(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
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
            if try await keychain.exists(.claudeAPIKey) {
                state = .saved
            } else {
                state = defaults.bool(forKey: Self.skippedKey) ? .skipped : .idle
            }
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

    /// Continues onboarding without a Claude key (AC2 "Überspringen"). Persisted
    /// via `UserDefaults` so the entry screen doesn't reappear on every cold
    /// start until the user actually adds a key.
    func skip() {
        defaults.set(true, forKey: Self.skippedKey)
        state = .skipped
    }
}
