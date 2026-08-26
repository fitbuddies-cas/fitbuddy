import Foundation

/// Streams an on-demand training analysis (US-3, #29).
///
/// The key it calls with comes from the user's provider priority order
/// (`LLMPriorityStore`, US-4 step 3) — see `storedAPIKey()`. Only the Claude
/// endpoint is implemented in v0; Gemini and Mistral request handling lands
/// with #79.
///
/// Rejects a call before any network request when one is already running or
/// the 6h cooldown has not elapsed — `AnalysisViewModel` (#31) also disables
/// the button, but the actor enforces both independently so no caller can
/// race past them. The cooldown itself is recorded only once Claude accepts
/// the request (HTTP 2xx): a failed attempt (missing key, offline, rate
/// limit) must not lock the user out until the next window.
actor InferenceService {
    /// Model used for every analysis call.
    static let model = "claude-opus-5"
    /// A training recommendation is a short, focused paragraph, not a
    /// code-generation-scale response — capped well below the model's ceiling
    /// so a malformed prompt cannot run up an unbounded bill on the user's
    /// own key.
    static let maxTokens = 4096

    private static let endpoint = URL(staticString: "https://api.anthropic.com/v1/messages")
    private static let anthropicVersion = "2023-06-01"
    private static let dataLinePrefix = "data:"

    private let session: URLSession
    private let keychain: KeychainService
    private let priority: LLMPriorityStore
    private let cooldown: AnalysisCooldownStore
    private let now: () -> Date
    private let decoder = JSONDecoder()

    /// Whether a stream is currently in flight. `private(set)` rather than
    /// `private`: tests poll it (same module) to wait out an async cleanup
    /// instead of guessing at a fixed delay; app code cannot write it.
    private(set) var isRunning = false

    /// - Parameters:
    ///   - session: Injectable for tests (stub `URLProtocol`); defaults to
    ///     `.fitBuddyStreaming`, whose longer idle timeout (NFR: ~30s) fits a
    ///     streaming call — `.fitBuddy`'s 15s does not reliably compose with a
    ///     per-request override.
    ///   - priority: The provider order the user set in onboarding step 3
    ///     (US-4), which decides whose key this call is made with.
    ///   - now: Injectable clock, so the cooldown window is testable.
    init(
        session: URLSession = .fitBuddyStreaming,
        keychain: KeychainService = KeychainService(),
        priority: LLMPriorityStore = LLMPriorityStore(),
        cooldown: AnalysisCooldownStore = AnalysisCooldownStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.keychain = keychain
        self.priority = priority
        self.cooldown = cooldown
        self.now = now
    }

    /// Streams incremental text chunks for `userPrompt` under `systemPrompt`
    /// (the prompt built by #30).
    ///
    /// Cancelling the consuming task stops the underlying request. Reaching
    /// the end of the stream without error is the only path that counts as a
    /// successful call for cooldown purposes — a cancellation midway still
    /// counts, since Claude already accepted and started billing the request;
    /// only a rejection before that point (bad key, offline, 4xx/5xx) does not.
    func streamAnalysis(systemPrompt: String, userPrompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard !isRunning else { throw InferenceServiceError.alreadyInProgress }
        // Claim the slot before the first `await` below: an actor releases its
        // isolation at every suspension point, so two truly concurrent callers
        // would otherwise both pass the guard above before either sets
        // `isRunning`. Released again on every early-exit path in the `catch`.
        isRunning = true
        let request: URLRequest
        do {
            if let availableAt = await cooldown.activeCooldown(now: now()) {
                throw InferenceServiceError.cooldownActive(availableAt: availableAt)
            }
            let apiKey = try await storedAPIKey()
            request = try makeRequest(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey)
        } catch {
            isRunning = false
            throw error
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(request, continuation: continuation)
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

    // MARK: - Streaming

    private func run(_ request: URLRequest, continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            // A cancelled call (user tapped cancel) is not a connectivity
            // problem and must not surface as one.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw error
            }
            throw InferenceServiceError.networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw InferenceServiceError.invalidResponse
        }
        try validate(http)
        // Claude accepted the request — it is billing tokens from here on,
        // regardless of whether the caller later cancels or a parse error
        // cuts the stream short.
        await cooldown.recordCall(at: now())

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix(Self.dataLinePrefix) else { continue }
            // SSE permits `data:value` without the space `data: value` shows in
            // every example — trim rather than assume the space is always there.
            let payload = line.dropFirst(Self.dataLinePrefix.count).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try? decoder.decode(ClaudeStreamEvent.self, from: data) else { continue }
            switch event.type {
            case "content_block_delta":
                if let text = event.delta?.text { continuation.yield(text) }
            case "error":
                // Claude can abort a stream after already answering 200 (e.g.
                // an overload mid-generation) — without this, the loop simply
                // reaches the end of input and the call looks like a normal,
                // if short, success.
                throw InferenceServiceError.streamInterrupted(message: event.error?.message ?? "unknown")
            default:
                continue
            }
        }
    }

    private func finish() {
        isRunning = false
    }

    // MARK: - Request

    private func makeRequest(systemPrompt: String, userPrompt: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        // Idle timeout (NFR: ~30s) comes from the session's
        // `timeoutIntervalForRequest` (`.fitBuddyStreaming`), not a per-request
        // override here — the two do not reliably compose.
        request.httpBody = try JSONEncoder().encode(
            ClaudeMessageRequest(
                model: Self.model,
                maxTokens: Self.maxTokens,
                system: systemPrompt,
                stream: true,
                messages: [ClaudeMessageRequest.Message(role: "user", content: userPrompt)]
            )
        )
        return request
    }

    // MARK: - Error mapping

    private func validate(_ http: HTTPURLResponse) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw InferenceServiceError.unauthorized
        case 429:
            throw InferenceServiceError.rateLimited(retryAfter: Self.retryAfter(from: http))
        case 500...599:
            throw InferenceServiceError.serviceUnavailable
        default:
            throw InferenceServiceError.unexpectedStatus(http.statusCode)
        }
    }

    private static func retryAfter(from http: HTTPURLResponse) -> TimeInterval? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(raw.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Helpers

    /// Resolves the key to call with by walking the provider priority order the
    /// user set in onboarding step 3 (US-4): the first provider that this build
    /// can call and that has a key stored wins. Providers stored but not yet
    /// implemented are skipped, so a Claude key in slot 2 is still used when
    /// slot 1 holds Gemini.
    private func storedAPIKey() async throws -> String {
        let order = await priority.order
        // An empty order means the Claude key predates the multi-provider step
        // (#78) — that install has exactly one key and no stored order.
        let providers = order.isEmpty ? [LLMProvider.claude] : order

        for provider in providers where provider.isCallable {
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
            if let key = stored, !key.isEmpty { return key }
        }

        // Distinguish "you have no key" from "your keys are for providers this
        // version cannot call yet": the second is not fixed by re-entering the
        // same key, so it must not surface as `.missingAPIKey`.
        if let configured = providers.first, !providers.contains(where: \.isCallable) {
            throw InferenceServiceError.providerNotSupportedYet(configured)
        }
        throw InferenceServiceError.missingAPIKey
    }
}
