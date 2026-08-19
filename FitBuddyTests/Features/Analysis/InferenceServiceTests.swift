import XCTest
@testable import FitBuddy

/// Unit tests for `InferenceService` using a stubbed `URLProtocol` — no real
/// network traffic. Keychain access uses the real `KeychainService` on the
/// simulator; the cooldown timestamp lives in an isolated `UserDefaults` suite.
final class InferenceServiceTests: XCTestCase {
    /// Fixed clock so cooldown math is deterministic.
    private static let now = Date(timeIntervalSince1970: 1_788_000_000)

    private var keychain: KeychainService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cooldown: AnalysisCooldownStore!
    private var sut: InferenceService!

    /// Last request the stub answered.
    nonisolated(unsafe) private static var captured: URLRequest?

    override func setUp() async throws {
        try await super.setUp()
        Self.captured = nil
        keychain = KeychainService()
        try await keychain.delete(.claudeAPIKey)
        try await keychain.save("sk-ant-test", for: .claudeAPIKey)
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        cooldown = AnalysisCooldownStore(defaults: defaults)
        sut = makeService()
    }

    override func tearDown() async throws {
        StubURLProtocol.handler = nil
        Self.captured = nil
        try await keychain.delete(.claudeAPIKey)
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        cooldown = nil
        defaults = nil
        keychain = nil
        try await super.tearDown()
    }

    private func makeService() -> InferenceService {
        InferenceService(session: StubURLProtocol.makeSession(), keychain: keychain, cooldown: cooldown, now: { Self.now })
    }

    // MARK: - Stubbing

    private func stubSuccess(textChunks: [String]) {
        let body = ClaudeSSEFactory.body(textChunks: textChunks)
        StubURLProtocol.handler = { request in
            Self.captured = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, body)
        }
    }

    private func stubFailure(statusCode: Int, headers: [String: String] = [:]) {
        StubURLProtocol.handler = { request in
            Self.captured = request
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
            return (response, Data())
        }
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var chunks: [String] = []
        for try await chunk in stream { chunks.append(chunk) }
        return chunks
    }

    /// `URLProtocol`-backed sessions sometimes hand the body over as a stream
    /// rather than `httpBody` — read whichever is populated.
    private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // MARK: - Streaming (AC: Streaming-Output erscheint inkrementell)

    func testStreamsIncrementalTextChunks() async throws {
        stubSuccess(textChunks: ["Increase ", "squat ", "by 2.5 kg."])

        let stream = try await sut.streamAnalysis(systemPrompt: "system", userPrompt: "user")
        let chunks = try await collect(stream)

        XCTAssertEqual(chunks, ["Increase ", "squat ", "by 2.5 kg."])
    }

    func testRequestShapeCarriesModelKeyAndPrompts() async throws {
        stubSuccess(textChunks: ["Hi"])

        _ = try await collect(try await sut.streamAnalysis(systemPrompt: "You are FitBuddy.", userPrompt: "Analyze my week."))

        let request = try XCTUnwrap(Self.captured)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")

        let body = try XCTUnwrap(bodyData(from: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, InferenceService.model)
        XCTAssertEqual(json["max_tokens"] as? Int, InferenceService.maxTokens)
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["system"] as? String, "You are FitBuddy.")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "Analyze my week.")
    }

    // MARK: - Missing key

    func testThrowsMissingAPIKeyBeforeAnyNetworkCall() async throws {
        try await keychain.delete(.claudeAPIKey)

        do {
            _ = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")
            XCTFail("expected missingAPIKey")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .missingAPIKey)
        }
        XCTAssertNil(Self.captured, "a missing key must not reach the network")
    }

    // MARK: - Cooldown (AC: Cooldown-Timer übersteht App-Neustart)

    func testThrowsCooldownActiveWhenCalledTooSoon() async throws {
        let lastCall = Self.now.addingTimeInterval(-1_000)
        await cooldown.recordCall(at: lastCall)

        do {
            _ = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")
            XCTFail("expected cooldownActive")
        } catch let error as InferenceServiceError {
            guard case .cooldownActive(let availableAt) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(availableAt, lastCall.addingTimeInterval(AnalysisCooldownStore.duration))
        }
        XCTAssertNil(Self.captured, "an active cooldown must not reach the network")
    }

    func testSucceedsOnceCooldownHasElapsed() async throws {
        await cooldown.recordCall(at: Self.now.addingTimeInterval(-AnalysisCooldownStore.duration - 1))
        stubSuccess(textChunks: ["Hi"])

        let chunks = try await collect(try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u"))

        XCTAssertEqual(chunks, ["Hi"])
    }

    func testRecordsCooldownAfterASuccessfulCall() async throws {
        stubSuccess(textChunks: ["Hi"])

        _ = try await collect(try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u"))

        let lastCall = await cooldown.lastCall()
        XCTAssertEqual(lastCall, Self.now)
    }

    func testDoesNotRecordCooldownWhenClaudeRejectsTheKey() async throws {
        stubFailure(statusCode: 401)

        do {
            _ = try await collect(try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u"))
            XCTFail("expected unauthorized")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .unauthorized)
        }
        let lastCall = await cooldown.lastCall()
        XCTAssertNil(lastCall, "a rejected request must not start the cooldown")
    }

    // MARK: - No double-submit (AC: kein zweiter Call möglich während laufendem Call)

    func testRejectsAConcurrentCallWhileOneIsRunning() async throws {
        stubSuccess(textChunks: ["Hi"])
        let stream = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")

        do {
            _ = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")
            XCTFail("expected alreadyInProgress")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .alreadyInProgress)
        }

        // Drain so the first call's internal task does not outlive the test.
        _ = try? await collect(stream)
    }

    func testAllowsANewCallAfterThePreviousOneFinished() async throws {
        stubSuccess(textChunks: ["First"])
        _ = try await collect(try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u"))
        // Isolates the `isRunning` reset from the (separately tested) cooldown:
        // the fixed clock would otherwise make this second call look like it
        // arrived seconds after the first, well inside the 6h window.
        await cooldown.clear()

        stubSuccess(textChunks: ["Second"])
        let chunks = try await collect(try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u"))

        XCTAssertEqual(chunks, ["Second"])
    }

    func testAllowsANewCallAfterTheConsumerCancelledThePreviousOne() async throws {
        stubSuccess(textChunks: Array(repeating: "chunk ", count: 20))
        let stream = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")
        let consumer = Task {
            for try await _ in stream {}
        }
        consumer.cancel()
        _ = try? await consumer.value

        // The actor clears `isRunning` from within its own internal task, which
        // races the assertion below without this: give it a moment to finish.
        try await Task.sleep(nanoseconds: 200_000_000)

        stubSuccess(textChunks: ["ok"])
        let chunks = try await collect(try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u"))
        XCTAssertEqual(chunks, ["ok"])
    }

    // MARK: - Error mapping

    func testNetworkUnavailableWhenTransportFails() async throws {
        struct TransportFailure: Error {}
        StubURLProtocol.handler = { _ in throw TransportFailure() }

        do {
            _ = try await collect(try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u"))
            XCTFail("expected networkUnavailable")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .networkUnavailable)
        }
    }

    func testRateLimitedCarriesRetryAfter() async throws {
        stubFailure(statusCode: 429, headers: ["Retry-After": "30"])

        do {
            _ = try await collect(try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u"))
            XCTFail("expected rateLimited")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 30))
        }
    }

    func testServiceUnavailableOnServerError() async throws {
        stubFailure(statusCode: 503)

        do {
            _ = try await collect(try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u"))
            XCTFail("expected serviceUnavailable")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .serviceUnavailable)
        }
    }
}
