import Foundation

/// Drives the consent screen (US-4, step 1): tracks the checkbox, persists
/// consent (version + timestamp) to the Keychain, and exposes the resulting
/// `ConsentState` used to gate the app's root view.
@MainActor
final class ConsentViewModel: ObservableObject {
    /// Version of the consent text currently shown. Bump this whenever the
    /// data processing described in the consent changes, so existing users are
    /// asked to consent again.
    static let currentVersion = "2026-08-21"

    /// Whether the user ticked the consent checkbox.
    @Published var hasAcceptedCheckbox = false
    /// Current gating state for the root view.
    @Published private(set) var state: ConsentState = .unknown
    /// True while a save is in flight (disables the confirm button).
    @Published private(set) var isSaving = false
    /// User-facing error message when persisting consent fails.
    @Published private(set) var errorMessage: String?

    /// The confirm button is enabled only with a ticked checkbox and no
    /// in-flight save.
    var canConfirm: Bool { hasAcceptedCheckbox && !isSaving }

    /// Invoked when the user actively confirms consent (not on a bootstrap
    /// restore) — lets the onboarding coordinator advance to step 2.
    var onGranted: (() -> Void)?

    private let keychain: KeychainService
    private let firstLaunchReset: FirstLaunchResetService

    init(
        keychain: KeychainService = KeychainService(),
        firstLaunchReset: FirstLaunchResetService? = nil
    ) {
        self.keychain = keychain
        // Share a single KeychainService instance with the reset service so both
        // collaborators address the Keychain through the same actor instance.
        self.firstLaunchReset = firstLaunchReset ?? FirstLaunchResetService(keychain: keychain)
    }

    /// Startup entry point for the gate: clears stale Keychain state on a fresh
    /// install (so a reinstall re-shows consent), then evaluates `state`.
    func bootstrap() async {
        try? await firstLaunchReset.resetIfFirstLaunch()
        await refreshState()
    }

    /// Reads stored consent and sets `state` to `.granted` only if both the
    /// current version and a timestamp are present; otherwise `.required`. The
    /// timestamp check guards against a partial write (version saved, timestamp
    /// not) leaving the user grantable without a recorded consent time.
    func refreshState() async {
        do {
            let storedVersion = try await keychain.read(.consentVersion)
            let storedTimestamp = try await keychain.read(.consentTimestamp)
            let isGranted = storedVersion == Self.currentVersion && storedTimestamp != nil
            state = isGranted ? .granted : .required
        } catch {
            // Treat a Keychain read failure as "consent needed" — never let the
            // user into the app without a confirmed consent.
            state = .required
        }
    }

    /// Persists the current consent version and an ISO8601 timestamp, then
    /// transitions to `.granted`. No-op without a ticked checkbox.
    func confirm() async {
        guard hasAcceptedCheckbox else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            try await keychain.save(Self.currentVersion, for: .consentVersion)
            try await keychain.save(timestamp, for: .consentTimestamp)
            state = .granted
            onGranted?()
        } catch {
            errorMessage = "Consent could not be saved. Please try again."
        }
    }
}
