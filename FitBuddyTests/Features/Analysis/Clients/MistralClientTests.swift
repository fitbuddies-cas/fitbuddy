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
        // Not sent until it has been seen accepted by Medium 3.5 (#211): on a
        // model it is not enabled for, Mistral answers the field with a 400.
        XCTAssertNil(json["reasoning_effort"])

        // OpenAI-shaped: the system prompt is the first message, not a field.
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.first?["content"] as? String, "You are FitBuddy.")
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        XCTAssertEqual(messages.last?["content"] as? String, "Analyze my week.")
    }

    /// The id Mistral documents and bills Medium 3.5 under, not one of its
    /// undocumented aliases (#211).
    func testPinsTheDocumentedModelId() {
        XCTAssertEqual(MistralClient.model, "mistral-medium-3-5")
    }

    func testReportsItsProvider() {
        XCTAssertEqual(sut.provider, .mistral)
    }

    // MARK: - Structured output (#174)

    func testRequestAsksForTheReportSchemaInStrictMode() async throws {
        stub(body: MistralSSEFactory.body(textChunks: ["Hi"]))

        _ = try await collect(try await stream())

        let json = try jsonBody(of: try capturedRequest())
        let format = try XCTUnwrap(json["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, AnalysisReportSchema.name)
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        let schema = try XCTUnwrap(jsonSchema["schema"] as? NSDictionary)
        XCTAssertEqual(schema, try jsonObject(of: AnalysisReportSchema.schema))
    }

    func testAStreamedJSONAnswerDecodesAsAReport() async throws {
        stub(body: MistralSSEFactory.body(textChunks: AnalysisReportFactory.progressChunks()))

        let event = try await parsedAnswer(of: try await stream())

        XCTAssertEqual(event, .report(AnalysisReportFactory.progress))
    }

    // MARK: - Stream parsing

    func testStreamsIncrementalTextChunks() async throws {
        stub(body: MistralSSEFactory.body(textChunks: ["Increase ", "squat ", "by 2.5 kg."]))

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, ["Increase ", "squat ", "by 2.5 kg."])
    }

    /// With reasoning on, `delta.content` is a chunk array while the model
    /// thinks. Thinking must not leak into the answer, and the text chunk in
    /// the same delta must not be dropped (#211).
    func testThinkingChunksAreDroppedAndTextChunksKept() async throws {
        stub(body: MistralSSEFactory.bodyWithThinkingChunks(
            thinking: "The user squats three times a week.",
            leadingText: "Increase ",
            textChunks: ["squat ", "by 2.5 kg."]
        ))

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, ["Increase ", "squat ", "by 2.5 kg."])
    }

    /// The array is decoded in one go, so one entry the decoder does not
    /// know must not take the text chunk beside it down with it (#211).
    func testChunkWithoutATypeDoesNotDropTheTextChunkBesideIt() async throws {
        stub(body: MistralSSEFactory.bodyWithContentChunks(
            [
                ["thinking": [["type": "text", "text": "Hmm."]]],
                ["type": "text", "text": "Increase "]
            ],
            textChunks: ["squat."]
        ))

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, ["Increase ", "squat."])
    }

    func testStopsAtTheDoneSentinel() async throws {
        // `[DONE]` is not JSON. Without the explicit stop it would be skipped as
        // undecodable and anything after it would still be read as answer text.
        stub(body: MistralSSEFactory.bodyWithTrailingNoise(textChunks: ["Real answer."]))

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, ["Real answer."])
    }

    // MARK: - Rejection before acceptance

    /// The same post-200 gap as Gemini's: an error frame carries no content and
    /// would otherwise be skipped, ending the run as a silent success.
    func testErrorFrameAfterTheStatusCodeInterruptsTheStream() async throws {
        stub(body: MistralSSEFactory.errorBody(type: "service_tier_capacity_exceeded", message: "capacity exceeded"))

        do {
            _ = try await collect(try await stream())
            XCTFail("expected streamInterrupted")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .streamInterrupted(message: "capacity exceeded"))
        }
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

    /// The 429 a workspace without pay-as-you-go gets on every call: the
    /// allowance header reads 0, and no amount of waiting changes that (#211).
    func testZeroAllowanceIsAPlanRestrictionNotARateLimit() async throws {
        stub(statusCode: 429, headers: ["x-ratelimit-limit-req-minute": "0"])

        do {
            _ = try await stream()
            XCTFail("expected planExcludesModel")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .planExcludesModel)
        }
    }

    /// A real burst limit keeps the allowance header above zero and stays an
    /// ordinary rate limit.
    func testNonZeroAllowanceStaysARateLimit() async throws {
        stub(statusCode: 429, headers: ["x-ratelimit-limit-req-minute": "750"])

        do {
            _ = try await stream()
            XCTFail("expected rateLimited")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .rateLimited(retryAfter: nil))
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

    // MARK: - Sampling (#226)

    /// `random_seed`, not OpenAI's `seed` — Mistral renamed the field, and the
    /// wrong key would be ignored rather than rejected.
    func testRequestCarriesTheSharedTemperatureAndSeed() async throws {
        stub(body: MistralSSEFactory.body(textChunks: ["Hi"]))

        _ = try await collect(try await stream())

        let json = try jsonBody(of: try capturedRequest())
        XCTAssertEqual(json["temperature"] as? Double, LLMSampling.temperature)
        XCTAssertEqual(json["random_seed"] as? Int, LLMSampling.seed)
        XCTAssertNil(json["seed"])
    }

    /// The point of the seed is that it does not move between runs.
    func testTheSeedIsTheSameOnEveryRun() async throws {
        stub(body: MistralSSEFactory.body(textChunks: ["Hi"]))
        _ = try await collect(try await stream())
        let first = try jsonBody(of: try capturedRequest())

        stub(body: MistralSSEFactory.body(textChunks: ["Hi"]))
        _ = try await collect(try await stream())
        let second = try jsonBody(of: try capturedRequest())

        XCTAssertEqual(first["random_seed"] as? Int, second["random_seed"] as? Int)
    }
}
