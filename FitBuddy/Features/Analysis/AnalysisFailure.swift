import Foundation

/// Why an analysis run did not produce a recommendation — the reason the
/// analysis screen names (#31, #79).
///
/// Coarser than `InferenceServiceError`, in the same spirit as `SyncFailure`:
/// the user needs to know whether to wait, retry, or fix something. The
/// distinctions that survive are the ones that change what they should do.
///
/// Every case that describes a provider's behaviour carries the provider it
/// describes. After a fallback chain that is the *last* one tried, which is the
/// one whose message tells the user what state they are actually in — the
/// providers tried before it are listed separately by the error view.
enum AnalysisFailure: Equatable {
    /// No provider has a key stored — the user has to add one.
    case missingAPIKey
    /// The Keychain read failed (e.g. a locked device). The key is still
    /// there, so this is a retry, not a reason to re-enter it.
    case keychainUnavailable
    /// The provider rejected the stored key (HTTP 401/403).
    case unauthorized(LLMProvider?)
    /// The request never reached the provider.
    case offline(LLMProvider?)
    /// HTTP 429, with the provider's `Retry-After` in seconds when it sent one.
    case rateLimited(provider: LLMProvider?, retryAfter: TimeInterval?)
    /// The provider's plan for this key allows no requests to the model at
    /// all (#211). Waiting does not help; the user has to change the plan.
    case planExcludesModel(LLMProvider?)
    /// The provider answered 5xx, or aborted the stream after answering 200.
    case serviceUnavailable(LLMProvider?)
    /// The cached window holds no workouts at all — not even in the widest
    /// rung of the fallback ladder (#87). There is nothing to analyse, and
    /// sending an empty prompt would spend the user's tokens on it.
    case noTrainingData
    /// The local cache could not be read.
    case cacheUnavailable
    /// The provider answered, but not with anything this version could read —
    /// an unexpected status, or a stream that ended without a single token.
    case unreadableResponse(LLMProvider?)

    /// Maps an inference or cache error onto a failure the screen can explain.
    ///
    /// - Parameter provider: The provider the error came from — the last one
    ///   the fallback chain tried. `nil` when the run failed before any
    ///   provider was picked, or when the cache, not a provider, failed.
    ///
    /// `.alreadyInProgress` has no case of its own: `AnalysisViewModel.start()`
    /// claims its slot synchronously, so a double tap cannot reach the service
    /// twice, and the actor's guard firing would mean two ViewModels share one
    /// service — a wiring bug, not something to tell the user about. It reads
    /// as `.unreadableResponse`, the generic bucket.
    init(analysisError: Error, provider: LLMProvider? = nil) {
        guard let error = analysisError as? InferenceServiceError else {
            self = .cacheUnavailable
            return
        }
        switch error {
        case .missingAPIKey:
            self = .missingAPIKey
        case .keychainUnavailable:
            self = .keychainUnavailable
        case .unauthorized:
            self = .unauthorized(provider)
        case .networkUnavailable:
            self = .offline(provider)
        case .rateLimited(let retryAfter):
            self = .rateLimited(provider: provider, retryAfter: retryAfter)
        case .planExcludesModel:
            self = .planExcludesModel(provider)
        case .serviceUnavailable, .streamInterrupted:
            self = .serviceUnavailable(provider)
        case .invalidResponse, .unexpectedStatus, .alreadyInProgress:
            self = .unreadableResponse(provider)
        }
    }

    /// The headline the analysis screen shows in place of a recommendation.
    var title: String {
        switch self {
        case .missingAPIKey:
            return "No API key stored"
        case .unauthorized(let provider):
            return "\(Self.name(provider)) key problem"
        case .keychainUnavailable:
            return "Key not readable"
        case .offline:
            return "No connection"
        case .rateLimited:
            return "Too many requests"
        case .planExcludesModel(let provider):
            return "\(Self.name(provider)) plan excludes this model"
        case .serviceUnavailable(let provider):
            return "\(Self.name(provider)) unavailable"
        case .noTrainingData:
            return "No training data"
        case .cacheUnavailable:
            return "Training data not readable"
        case .unreadableResponse:
            return "Unexpected response"
        }
    }

    /// One line saying what to do about it. Always actionable: an error
    /// message the user cannot act on is just a spinner that stopped moving.
    var message: String {
        switch self {
        case .missingAPIKey:
            return "No API key is stored for any provider. Add one in Settings to run an analysis."
        case .unauthorized(let provider):
            return "\(Self.name(provider)) rejected your API key. Check it and enter it again."
        case .keychainUnavailable:
            return "Your key could not be read from the Keychain. Unlock your device and try again."
        case .offline(let provider):
            return "Your device could not reach \(Self.name(provider)). Check your connection and try again."
        case .rateLimited(let provider, let retryAfter):
            guard let wait = Self.wait(retryAfter) else {
                return "\(Self.name(provider)) is rate-limiting your key. Try again in a few minutes."
            }
            return "\(Self.name(provider)) is rate-limiting your key. Try again in \(wait)."
        case .planExcludesModel(let provider):
            return "\(Self.name(provider)) allows no requests to the model FitBuddy uses on your current plan. "
                + "Enable pay-as-you-go there, then run the analysis again."
        case .serviceUnavailable(let provider):
            return "\(Self.name(provider)) could not complete the analysis. Try again in a few minutes."
        case .noTrainingData:
            return "There are no workouts in your cached training data to analyse. Sync it first."
        case .cacheUnavailable:
            return "Your cached training data could not be read. Try again after a sync."
        case .unreadableResponse(let provider):
            return "\(Self.name(provider))'s answer could not be read. Try again in a few minutes."
        }
    }

    /// The symbol shown above the message.
    var symbolName: String {
        switch self {
        case .missingAPIKey, .unauthorized:
            return "key.slash"
        case .keychainUnavailable:
            return "lock.slash"
        case .offline:
            return "antenna.radiowaves.left.and.right.slash"
        case .rateLimited, .serviceUnavailable:
            return "exclamationmark.icloud"
        case .planExcludesModel:
            return "creditcard.trianglebadge.exclamationmark"
        case .noTrainingData:
            return "figure.strengthtraining.traditional"
        case .cacheUnavailable:
            return "externaldrive.badge.exclamationmark"
        case .unreadableResponse:
            return "questionmark.circle"
        }
    }

    /// Whether tapping "Try again" can plausibly help. A missing or rejected
    /// key cannot be retried into working — that one needs onboarding.
    var isRetryable: Bool {
        switch self {
        case .missingAPIKey, .unauthorized, .noTrainingData, .planExcludesModel:
            return false
        case .keychainUnavailable, .offline, .rateLimited, .serviceUnavailable,
             .cacheUnavailable, .unreadableResponse:
            return true
        }
    }

    /// Whether the fix lives on the settings tab, so the error screen can
    /// offer the way there instead of a retry that would fail the same way
    /// (#207).
    ///
    /// Only the missing key: a rejected key (`unauthorized`) is also fixed in
    /// settings, but the user first has to find out from the provider which
    /// key is right, and sending them straight to the editor would suggest
    /// that re-typing the same one helps.
    var leadsToSettings: Bool {
        if case .missingAPIKey = self { return true }
        return false
    }

    /// Where the plan is changed, for the failure whose fix is a billing
    /// setting in the provider's console (#211). `nil` for every other
    /// failure, and for providers that never report a plan restriction.
    var planURL: URL? {
        guard case .planExcludesModel(.mistral) = self else { return nil }
        // The Limits page shows the zero allowance and the current tier, and
        // links on to Billing where pay-as-you-go is switched on.
        return URL(staticString: "https://admin.mistral.ai/plateforme/limits")
    }

    /// The provider's name, or a neutral stand-in when the run failed before
    /// one was picked — the message still has to read as a sentence.
    private static func name(_ provider: LLMProvider?) -> String {
        provider?.displayName ?? "The provider"
    }

    /// `30` → `"30 s"`, `180` → `"3 min"`. `nil` when the provider sent no
    /// usable value, so the caller drops the clause instead of printing "0 s".
    private static func wait(_ retryAfter: TimeInterval?) -> String? {
        guard let retryAfter, retryAfter >= 1 else { return nil }
        guard retryAfter >= 90 else { return "\(Int(retryAfter.rounded())) s" }
        return "\(Int((retryAfter / 60).rounded())) min"
    }

}
