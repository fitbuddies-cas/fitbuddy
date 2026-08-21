import Foundation

/// Why an analysis run did not produce a recommendation — the reason the
/// analysis screen names (#31).
///
/// Coarser than `InferenceServiceError`, in the same spirit as `SyncFailure`:
/// the user needs to know whether to wait, retry, or fix something. The
/// distinctions that survive are the ones that change what they should do.
enum AnalysisFailure: Equatable {
    /// No Claude key stored — the user has to add one in onboarding.
    case missingAPIKey
    /// The Keychain read failed (e.g. a locked device). The key is still
    /// there, so this is a retry, not a reason to re-enter it.
    case keychainUnavailable
    /// Claude rejected the stored key (HTTP 401).
    case unauthorized
    /// The request never reached Claude.
    case offline
    /// HTTP 429, with Claude's `Retry-After` in seconds when it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    /// Claude answered 5xx, or aborted the stream after answering 200.
    case serviceUnavailable
    /// The 6h cooldown was still running when the call went out. Carries the
    /// instant it ends, so the message can name it.
    case cooldownActive(availableAt: Date)
    /// The cached window holds no workouts — there is nothing to analyse, and
    /// sending an empty prompt would spend the user's tokens on it.
    case noTrainingData
    /// The local cache could not be read.
    case cacheUnavailable
    /// Claude answered, but not with anything this version could read — an
    /// unexpected status, or a stream that ended without a single token.
    case unreadableResponse

    /// Maps an inference or cache error onto a failure the screen can explain.
    ///
    /// `.alreadyInProgress` has no case of its own: the ViewModel's own state
    /// machine already prevents a second run, so the actor's guard firing
    /// would mean two ViewModels share one service — a wiring bug, not
    /// something to tell the user about. It reads as `.unreadableResponse`,
    /// the generic bucket.
    init(analysisError: Error) {
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
            self = .unauthorized
        case .networkUnavailable:
            self = .offline
        case .rateLimited(let retryAfter):
            self = .rateLimited(retryAfter: retryAfter)
        case .serviceUnavailable, .streamInterrupted:
            self = .serviceUnavailable
        case .cooldownActive(let availableAt):
            self = .cooldownActive(availableAt: availableAt)
        case .invalidResponse, .unexpectedStatus, .alreadyInProgress:
            self = .unreadableResponse
        }
    }

    /// The headline the analysis screen shows in place of a recommendation.
    var title: String {
        switch self {
        case .missingAPIKey, .unauthorized:
            return "Claude key problem"
        case .keychainUnavailable:
            return "Key not readable"
        case .offline:
            return "No connection"
        case .rateLimited:
            return "Too many requests"
        case .serviceUnavailable:
            return "Claude unavailable"
        case .cooldownActive:
            return "Analysis on cooldown"
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
            return "No Claude API key is stored. Add your key to run an analysis."
        case .unauthorized:
            return "Claude rejected your API key. Check it and enter it again."
        case .keychainUnavailable:
            return "Your key could not be read from the Keychain. Unlock your device and try again."
        case .offline:
            return "Your device could not reach Claude. Check your connection and try again."
        case .rateLimited(let retryAfter):
            guard let wait = Self.wait(retryAfter) else {
                return "Claude is rate-limiting your key. Try again in a few minutes."
            }
            return "Claude is rate-limiting your key. Try again in \(wait)."
        case .serviceUnavailable:
            return "Claude could not complete the analysis. Try again in a few minutes."
        case .cooldownActive(let availableAt):
            // The instant, not a countdown: this message is written once, while
            // `AnalysisViewModel.cooldownMessage` keeps ticking beside it.
            return "You have already run an analysis in the last 6 hours. "
                + "The next one is available at \(Self.clockTime(availableAt))."
        case .noTrainingData:
            return "There are no workouts in the last 4 weeks to analyse. Sync your training data first."
        case .cacheUnavailable:
            return "Your cached training data could not be read. Try again after a sync."
        case .unreadableResponse:
            return "Claude's answer could not be read. Try again in a few minutes."
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
        case .cooldownActive:
            return "hourglass"
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
        case .missingAPIKey, .unauthorized, .cooldownActive, .noTrainingData:
            return false
        case .keychainUnavailable, .offline, .rateLimited, .serviceUnavailable,
             .cacheUnavailable, .unreadableResponse:
            return true
        }
    }

    /// `30` → `"30 s"`, `180` → `"3 min"`. `nil` when Claude sent no usable
    /// value, so the caller drops the clause instead of printing "0 s".
    private static func wait(_ retryAfter: TimeInterval?) -> String? {
        guard let retryAfter, retryAfter >= 1 else { return nil }
        guard retryAfter >= 90 else { return "\(Int(retryAfter.rounded())) s" }
        return "\(Int((retryAfter / 60).rounded())) min"
    }

    /// Wall-clock time of day, in the user's own locale — the one place in the
    /// analysis screen where a device-local format is right, because the user
    /// reads it against their own clock.
    ///
    /// Built per call rather than cached in a `static let`: this renders once
    /// per failed run at most, and a shared mutable `DateFormatter` is not
    /// worth the concurrency caveat for that.
    private static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
