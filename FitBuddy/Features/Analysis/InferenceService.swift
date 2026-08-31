import Foundation

/// Runs an on-demand training analysis against the user's LLM providers,
/// falling back down their priority order until one answers (US-3, #29/#79).
///
/// Provider-specific work — endpoints, auth, body shapes, stream formats —
/// lives in `LLMProviderClient` implementations. This actor only decides *who*
/// to ask, in what order, and when to stop.
///
/// Rejects a call before any network request when one is already running or
/// the 6h cooldown has not elapsed — `AnalysisViewModel` (#31) also disables
/// the button, but the actor enforces both independently so no caller can
/// race past them. The cooldown itself is recorded once per run, the moment
/// the first provider accepts the request (HTTP 2xx): a run that never got
/// that far (no key, offline, every provider rejecting) must not lock the user
/// out until the next window, and a run that fell back twice must not spend
/// three windows.
actor InferenceService {
    private let keychain: KeychainService
    private let priority: LLMPriorityStore
    private let cooldown: AnalysisCooldownStore
    private let clients: [LLMProvider: any LLMProviderClient]
    private let now: () -> Date

    /// Whether a stream is currently in flight. `private(set)` rather than
    /// `private`: tests poll it (same module) to wait out an async cleanup
    /// instead of guessing at a fixed delay; app code cannot write it.
    private(set) var isRunning = false

    /// - Parameters:
    ///   - session: Injectable for tests (stub `URLProtocol`); defaults to
    ///     `.fitBuddyStreaming`, whose longer idle timeout (NFR: ~30s) fits a
    ///     streaming call — `.fitBuddy`'s 15s does not reliably compose with a
    ///     per-request override. Ignored when `clients` is passed explicitly.
    ///   - priority: The provider order the user set in onboarding step 3
    ///     (US-4), which decides who is asked first and who takes over.
    ///   - clients: Injectable per-provider callers, so orchestrator tests can
    ///     drive fallback without three stubbed endpoints.
    ///   - now: Injectable clock, so the cooldown window is testable.
    init(
        session: URLSession = .fitBuddyStreaming,
        keychain: KeychainService = KeychainService(),
        priority: LLMPriorityStore = LLMPriorityStore(),
        cooldown: AnalysisCooldownStore = AnalysisCooldownStore(),
        clients: [LLMProvider: any LLMProviderClient]? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.keychain = keychain
        self.priority = priority
        self.cooldown = cooldown
        self.clients = clients ?? Self.defaultClients(session: session)
        self.now = now
    }

    private static func defaultClients(session: URLSession) -> [LLMProvider: any LLMProviderClient] {
        let all: [any LLMProviderClient] = [
            AnthropicClient(session: session),
            GeminiClient(session: session),
            MistralClient(session: session)
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.provider, $0) })
    }

    /// Streams one analysis for `userPrompt` under `systemPrompt` (the prompt
    /// built by #30), trying each configured provider in priority order.
    ///
    /// Cancelling the consuming task stops the underlying request and ends the
    /// run — a cancellation is never treated as a provider failure, so it does
    /// not fall through to the next one.
    func streamAnalysis(systemPrompt: String, userPrompt: String) async throws -> AsyncThrowingStream<AnalysisEvent, Error> {
        guard !isRunning else { throw InferenceServiceError.alreadyInProgress }
        // Claim the slot before the first `await` below: an actor releases its
        // isolation at every suspension point, so two truly concurrent callers
        // would otherwise both pass the guard above before either sets
        // `isRunning`. Released again on every early-exit path in the `catch`.
        isRunning = true
        let candidates: [Candidate]
        do {
            if let availableAt = await cooldown.activeCooldown(now: now()) {
                throw InferenceServiceError.cooldownActive(availableAt: availableAt)
            }
            candidates = try await resolveCandidates()
        } catch {
            isRunning = false
            throw error
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(candidates, systemPrompt: systemPrompt, userPrompt: userPrompt, continuation: continuation)
                    await self.finish()
                    continuation.finish()
                } catch {
                    await self.finish()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Fallback chain

    /// A provider that can actually be tried: its client and its stored key.
    private struct Candidate {
        let client: any LLMProviderClient
        let apiKey: String
    }

    /// Walks the candidates in order until one produces an answer.
    ///
    /// Every failure — rejected key, no credit, rate limit, 5xx, transport
    /// error, a stream that dies mid-answer — moves on to the next provider.
    /// Only when the last one fails is its error raised, because that is the
    /// one whose message describes the state the user is actually left in.
    private func run(
        _ candidates: [Candidate],
        systemPrompt: String,
        userPrompt: String,
        continuation: AsyncThrowingStream<AnalysisEvent, Error>.Continuation
    ) async throws {
        var didRecordCooldown = false
        var lastError: Error = InferenceServiceError.missingAPIKey

        for candidate in candidates {
            try Task.checkCancellation()
            // Announced before the attempt, not after it succeeds: this is what
            // tells the screen whose name to show while it waits, and what tells
            // it to drop whatever a failed predecessor already streamed.
            continuation.yield(.attempting(candidate.client.provider))
            do {
                let stream = try await candidate.client.streamAnalysis(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    apiKey: candidate.apiKey
                )
                // The provider accepted and is billing tokens from here on,
                // regardless of whether the answer later fails or the user
                // cancels — but only the first such acceptance in a run spends
                // the window.
                if !didRecordCooldown {
                    await cooldown.recordCall(at: now())
                    didRecordCooldown = true
                }
                for try await chunk in stream {
                    try Task.checkCancellation()
                    continuation.yield(.text(chunk))
                }
                return
            } catch {
                // The user cancelled: not a provider problem, and asking the
                // next one would keep spending on a run nobody is waiting for.
                if Task.isCancelled || error.isCancellation { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Candidates

    /// The providers to try, in the order the user set in onboarding step 3
    /// (US-4), each paired with the key stored for it.
    ///
    /// A provider without a stored key is skipped rather than counted as a
    /// failure: it was never configured, so it has nothing to fall back from.
    private func resolveCandidates() async throws -> [Candidate] {
        let order = await priority.order
        // An empty order means the Claude key predates the multi-provider step
        // (#78) — that install has exactly one key and no stored order.
        let providers = order.isEmpty ? [LLMProvider.claude] : order

        var candidates: [Candidate] = []
        for provider in providers {
            guard let client = clients[provider] else { continue }
            let stored: String?
            do {
                stored = try await keychain.read(provider.keychainKey)
            } catch {
                // The read itself failed (e.g. `errSecInteractionNotAllowed` on
                // a locked device) — the key is still stored, so this must not
                // read as "no key" and send an onboarded user back to re-enter
                // one.
                throw InferenceServiceError.keychainUnavailable
            }
            guard let key = stored, !key.isEmpty else { continue }
            candidates.append(Candidate(client: client, apiKey: key))
        }

        guard !candidates.isEmpty else { throw InferenceServiceError.missingAPIKey }
        return candidates
    }

    private func finish() {
        isRunning = false
    }
}
