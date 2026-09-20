import XCTest
@testable import FitBuddy

/// Request shape and stream parsing for the Claude client, over a stubbed
/// `URLProtocol` — no real network traffic (#79; behaviour originally covered
/// by `InferenceServiceTests` under #29).
final class AnthropicClientTests: LLMClientTestCase {
    private var sut: AnthropicClient!

    override func setUp() async throws {
        try await super.setUp()
        sut = AnthropicClient(session: session)
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    private func stream() async throws -> AsyncThrowingStream<String, Error> {
        try await sut.streamAnalysis(systemPrompt: "You are FitBuddy.", userPrompt: "Analyze my week.", apiKey: "sk-ant-test")
    }

    // MARK: - Request shape

    func testRequestCarriesEndpointHeadersModelAndPrompts() async throws {
        stub(body: ClaudeSSEFactory.body(textChunks: ["Hi"]))

        _ = try await collect(try await stream())

        let request = try capturedRequest()
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")

        let json = try jsonBody(of: request)
        XCTAssertEqual(json["model"] as? String, AnthropicClient.model)
        XCTAssertEqual(json["max_tokens"] as? Int, AnthropicClient.maxTokens)
        // Thinking is on by default on this model and shares `max_tokens` with
        // the prose — the effort setting is what keeps the paragraph affordable.
        let outputConfig = try XCTUnwrap(json["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, AnthropicClient.effort)
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["system"] as? String, "You are FitBuddy.")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "Analyze my week.")
    }

    func testReportsItsProvider() {
        XCTAssertEqual(sut.provider, .claude)
    }

    // MARK: - Structured output (#174)

    func testRequestAsksForTheReportSchemaAlongsideTheEffort() async throws {
        stub(body: ClaudeSSEFactory.body(textChunks: ["Hi"]))

        _ = try await collect(try await stream())

        let json = try jsonBody(of: try capturedRequest())
        let outputConfig = try XCTUnwrap(json["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, AnthropicClient.effort)
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? NSDictionary)
        XCTAssertEqual(schema, try jsonObject(of: AnalysisReportSchema.schema))
    }

    func testAStreamedJSONAnswerDecodesAsAReport() async throws {
        stub(body: ClaudeSSEFactory.body(textChunks: AnalysisReportFactory.progressChunks()))

        let event = try await parsedAnswer(of: try await stream())

        XCTAssertEqual(event, .report(AnalysisReportFactory.progress))
    }

    // MARK: - Stream parsing

    func testStreamsIncrementalTextChunks() async throws {
        stub(body: ClaudeSSEFactory.body(textChunks: ["Increase ", "squat ", "by 2.5 kg."]))

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, ["Increase ", "squat ", "by 2.5 kg."])
    }

    func testStreamErrorEventAfterHTTP200SurfacesThroughTheStream() async throws {
        // Claude can abort after already answering 200 (e.g. `overloaded_error`).
        // The distinction matters to the orchestrator: this one has already cost
        // the user tokens, so it must arrive through the stream, not before it.
        stub(body: ClaudeSSEFactory.errorBody(type: "overloaded_error", message: "Overloaded"))

        let stream = try await stream()
        do {
            _ = try await collect(stream)
            XCTFail("expected streamInterrupted")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .streamInterrupted(message: "Overloaded"))
        }
    }

    func testStopReasonMaxTokensKeepsTheTruncatedTextAsAnAnswer() async throws {
        // Thinking shares `max_tokens` with the prose, so a reasoning-heavy run
        // can stop mid-sentence while HTTP 200 and a few chunks already
        // arrived. That text is still the model's own recommendation, so it is
        // kept — matching Gemini's `MAX_TOKENS` and Mistral's `length`. Throwing
        // here would, for the Claude-only setup, turn a usable answer into an
        // error with the tokens already billed.
        stub(body: ClaudeSSEFactory.body(textChunks: ["Increase squat"], stopReason: "max_tokens"))

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, ["Increase squat"])
    }

    func testStopReasonRefusalIsReportedAsAnInterruption() async throws {
        // A refusal arrives as a clean 200 as well.
        stub(body: ClaudeSSEFactory.body(textChunks: ["I cannot"], stopReason: "refusal"))

        do {
            _ = try await collect(try await stream())
            XCTFail("expected streamInterrupted")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .streamInterrupted(message: "refusal"))
        }
    }

    func testStopSequenceCountsAsACompleteAnswer() async throws {
        stub(body: ClaudeSSEFactory.body(textChunks: ["Done."], stopReason: "stop_sequence"))

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, ["Done."])
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
        stub(statusCode: 429, headers: ["Retry-After": "30"])

        do {
            _ = try await stream()
            XCTFail("expected rateLimited")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 30))
        }
    }

    func testServiceUnavailableOnServerError() async throws {
        stub(statusCode: 503)

        do {
            _ = try await stream()
            XCTFail("expected serviceUnavailable")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .serviceUnavailable)
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

    /// A failed certificate check (pinning, #153) is reported as such, not
    /// as offline — the prompt with the training data was never sent.
    func testUntrustedConnectionWhenCertificateCheckFails() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.serverCertificateUntrusted) }

        do {
            _ = try await stream()
            XCTFail("expected untrustedConnection")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .untrustedConnection)
        }
    }
}
