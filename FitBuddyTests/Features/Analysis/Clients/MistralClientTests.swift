import XCTest
@testable import FitBuddy

/// Request shape and stream parsing for the Mistral client, over a stubbed
/// `URLProtocol` — no real network traffic (#79).
final class MistralClientTests: LLMClientTestCase {
    private var sut: MistralClient!

    override func setUp() async throws {
        try await super.setUp()
        sut = MistralClient(session: session)
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    private func stream() async throws -> AsyncThrowingStream<String, Error> {
        try await sut.streamAnalysis(systemPrompt: "You are FitBuddy.", userPrompt: "Analyze my week.", apiKey: "mistral-test")
    }

    // MARK: - Request shape

    func testRequestCarriesEndpointBearerTokenModelAndPrompts() async throws {
        stub(body: MistralSSEFactory.body(textChunks: ["Hi"]))

        _ = try await collect(try await stream())

        let request = try capturedRequest()
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mistral-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")

        let json = try jsonBody(of: request)
        XCTAssertEqual(json["model"] as? String, MistralClient.model)
        XCTAssertEqual(json["max_tokens"] as? Int, MistralClient.maxTokens)
        XCTAssertEqual(json["stream"] as? Bool, true)

        // OpenAI-shaped: the system prompt is the first message, not a field.
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.first?["content"] as? String, "You are FitBuddy.")
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        XCTAssertEqual(messages.last?["content"] as? String, "Analyze my week.")
    }

    func testReportsItsProvider() {
        XCTAssertEqual(sut.provider, .mistral)
    }

    // MARK: - Stream parsing

    func testStreamsIncrementalTextChunks() async throws {
        stub(body: MistralSSEFactory.body(textChunks: ["Increase ", "squat ", "by 2.5 kg."]))

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, ["Increase ", "squat ", "by 2.5 kg."])
    }

    func testStopsAtTheDoneSentinel() async throws {
        // `[DONE]` is not JSON. Without the explicit stop it would be skipped as
        // undecodable and anything after it would still be read as answer text.
        stub(body: MistralSSEFactory.bodyWithTrailingNoise(textChunks: ["Real answer."]))

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, ["Real answer."])
    }

    // MARK: - Rejection before acceptance

    func testUnauthorizedThrowsBeforeReturningAStream() async throws {
        stub(statusCode: 401)

        do {
            _ = try await stream()
            XCTFail("expected unauthorized")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testRateLimitedCarriesRetryAfter() async throws {
        stub(statusCode: 429, headers: ["Retry-After": "45"])

        do {
            _ = try await stream()
            XCTFail("expected rateLimited")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 45))
        }
    }

    func testNetworkUnavailableWhenTransportFails() async throws {
        stubTransportFailure()

        do {
            _ = try await stream()
            XCTFail("expected networkUnavailable")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .networkUnavailable)
        }
    }
}
