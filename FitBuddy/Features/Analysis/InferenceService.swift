import Foundation

/// Runs an on-demand training analysis against the user's LLM providers,
/// falling back down their priority order until one answers (US-3, #29/#79).
///
/// Provider-specific work — endpoints, auth, body shapes, stream formats —
/// lives in `LLMProviderClient` implementations. This actor only decides *who*
/// to ask, in what order, and when to stop.
///
/// Rejects a call before any network request while one is already running —
/// `AnalysisViewModel` (#31) also disables the button, but the actor enforces
/// it independently so no caller can race past it. There is no cooldown after
/// a run: the 60s lock of #117 is gone, and the hard limit on spending is the
/// spending limit in the user's own provider account (ADR-004).
actor InferenceService {
    private let keychain: KeychainService
    private let priority: LLMPriorityStore
    private let clients: [LLMProvider: any LLMProviderClient]

    /// Whether a stream is currently in flight. `private(set)` rather than
    /// `private`: tests poll it (same module) to wait out an async cleanup
    /// instead of guessing at a fixed delay; app code cannot write it.
    private(set) var isRunning = false
    /// The task of the run holding the slot, so a new call can wait for a
    /// cancelled one to unwind instead of being refused.
    private var currentRun: Task<Void, Never>?

    /// - Parameters:
    ///   - session: Injectable for tests (stub `URLProtocol`); defaults to
    ///     `.fitBuddyStreaming`, whose longer idle timeout (NFR: ~30s) fits a
    ///     streaming call — `.fitBuddy`'s 15s does not reliably compose with a
    ///     per-request override. Ignored when `clients` is passed explicitly.
    ///   - priority: The provider order the user set in onboarding step 3
    ///     (US-4), which decides who is asked first and who takes over.
    ///   - clients: Injectable per-provider callers, so orchestrator tests can
    ///     drive fallback without three stubbed endpoints.
    init(
        session: URLSession = .fitBuddyStreaming,
        keychain: KeychainService = KeychainService(),
        priority: LLMPriorityStore = LLMPriorityStore(),
        clients: [LLMProvider: any LLMProviderClient]? = nil
    ) {
        self.keychain = keychain
        self.priority = priority
        self.clients = clients ?? Self.defaultClients(session: session)
    }

    private static func defaultClients(session: URLSession) -> [LLMProvider: any LLMProviderClient] {
        let all: [any LLMProviderClient] = [
            AnthropicClient(session: session),
            GeminiClient(session: session),
            MistralClient(session: session)
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.provider, $0) })
    }

    /// Runs one analysis for `userPrompt` under `systemPrompt` (the prompt
    /// built by #30), trying each configured provider in priority order.
    ///
    /// Each provider's answer is collected in full and yielded once, as a
    /// decoded `AnalysisReport` or as prose (#174).
    ///
    /// Cancelling the consuming task stops the underlying request and ends the
    /// run — a cancellation is never treated as a provider failure, so it does
    /// not fall through to the next one.
    ///
    /// A run the consumer has cancelled keeps the slot until its task has
    /// unwound. A call arriving in that moment — "Analyze" tapped right after
    /// "Cancel" — waits for it rather than failing with `.alreadyInProgress`;
    /// only a run that is still live refuses a second one.
    func streamAnalysis(systemPrompt: String, userPrompt: String) async throws -> AsyncThrowingStream<AnalysisEvent, Error> {
        while isRunning, let previous = currentRun, previous.isCancelled {
            await previous.value
        }
        guard !isRunning else { throw InferenceServiceError.alreadyInProgress }
        // Claim the slot before the first `await` below: an actor releases its
        // isolation at every suspension point, so two truly concurrent callers
        // would otherwise both pass the guard above before either sets
        // `isRunning`. Released again on every early-exit path in the `catch`.
        isRunning = true
        let candidates: [Candidate]
        do {
            candidates = try await resolveCandidates()
        } catch {
            isRunning = false
            throw error
        }

        let (stream, continuation) = AsyncThrowingStream<AnalysisEvent, Error>.makeStream()
        let task = Task {
            do {
                try await self.run(candidates, systemPrompt: systemPrompt, userPrompt: userPrompt, continuation: continuation)
                self.finish()
                continuation.finish()
            } catch {
                self.finish()
                continuation.finish(throwing: error)
            }
        }
        currentRun = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
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
                // Collected rather than forwarded chunk by chunk: the answer is
                // a JSON document (#174), and half of one is neither a report
                // nor readable prose. It also means a provider that dies
                // mid-answer never puts anything on screen.
                var answer = ""
                for try await chunk in stream {
                    try Task.checkCancellation()
                    answer += chunk
                }
                // A report, or prose when the answer does not match the schema
                // (US-14 AC5) — either one ends the run.
                if let event = AnalysisReportParser.event(for: answer) {
                    continuation.yield(event)
                    return
                }
                // Nothing to show is not an answer: hand over to the next
                // candidate rather than ending the run. That covers a clean
                // stream that never produced a token — a provider can answer
                // 200 and simply say nothing, or send an error frame its client
                // does not recognise — and a JSON answer cut off at the token
                // limit before its lead, which would otherwise reach the
                // screen as raw JSON.
                lastError = InferenceServiceError.invalidResponse
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
        // The same order the send-confirmation sheet showed the user (#268):
        // a provider the order does not name is appended, not dropped — see
        // `LLMProvider.fallbackOrder(from:)`.
        let providers = LLMProvider.fallbackOrder(from: await priority.order)

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
        currentRun = nil
    }
}
