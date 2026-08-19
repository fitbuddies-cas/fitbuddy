import Foundation

/// Streams an on-demand training analysis from Claude (US-3, #29).
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
    private static let dataLinePrefix = "data: "

    private let session: URLSession
    private let keychain: KeychainService
    private let cooldown: AnalysisCooldownStore
    private let now: () -> Date

    /// Whether a stream is currently in flight.
    private var isRunning = false

    /// - Parameters:
    ///   - session: Injectable for tests (stub `URLProtocol`); defaults to
    ///     `.fitBuddy`, the shared no-disk-cache session for key-bearing calls.
    ///   - now: Injectable clock, so the cooldown window is testable.
    init(
        session: URLSession = .fitBuddy,
        keychain: KeychainService = KeychainService(),
        cooldown: AnalysisCooldownStore = AnalysisCooldownStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.keychain = keychain
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
        if let availableAt = await cooldown.activeCooldown(now: now()) {
            throw InferenceServiceError.cooldownActive(availableAt: availableAt)
        }
        let apiKey = try await storedAPIKey()
        let request = try makeRequest(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey)

        isRunning = true
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
            throw InferenceServiceError.networkUnavailable
        }
        try validate(http)
        // Claude accepted the request — it is billing tokens from here on,
        // regardless of whether the caller later cancels or a parse error
        // cuts the stream short.
        await cooldown.recordCall(at: now())

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix(Self.dataLinePrefix) else { continue }
            let payload = line.dropFirst(Self.dataLinePrefix.count)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(ClaudeStreamEvent.self, from: data) else { continue }
            if event.type == "content_block_delta", let text = event.delta?.text {
                continuation.yield(text)
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
        // NFR: Claude can take up to ~30s; streamed chunks reset this per-request
        // idle timeout, so a healthy stream is never cut off mid-flow.
        request.timeoutInterval = 30
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

    private func storedAPIKey() async throws -> String {
        let stored: String?
        do {
            stored = try await keychain.read(.claudeAPIKey)
        } catch {
            throw InferenceServiceError.missingAPIKey
        }
        guard let key = stored, !key.isEmpty else { throw InferenceServiceError.missingAPIKey }
        return key
    }
}
