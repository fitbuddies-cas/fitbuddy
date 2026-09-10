import Foundation

// Test support: excluded from Release builds, so no stubbed validation can
// reach a TestFlight binary.
#if DEBUG

/// Answers key validation with a fixed verdict instead of calling Hevy (#120).
///
/// The UI tests have to drive both outcomes of onboarding step 2 — a key Hevy
/// accepts and one it rejects — and neither is available to them otherwise: a
/// real key cannot live in the repository, and a real call would make the test
/// depend on Hevy being up and on the network being there. This is the seam
/// that removes both, activated by `OnboardingViewModel.stubValidationArgument`
/// and never reachable in a shipped build.
///
/// An `actor` like `HevyKeyValidator`, so it is the same kind of collaborator
/// the view model has in production.
actor StubHevyKeyValidator: HevyKeyValidating {
    /// What the stub should pretend Hevy answered.
    enum Verdict: String {
        /// HTTP 200 — the key is accepted and gets stored.
        case accepts
        /// HTTP 401 — the key is rejected, nothing is stored.
        case rejects
    }

    private let verdict: Verdict

    init(verdict: Verdict) {
        self.verdict = verdict
    }

    func validate(_ apiKey: String) async throws {
        switch verdict {
        case .accepts:
            return
        case .rejects:
            throw HevyKeyValidationError.invalidKey
        }
    }
}

#endif
