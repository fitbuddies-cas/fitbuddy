import XCTest
@testable import FitBuddy

/// Request shape and stream parsing for the Gemini client, over a stubbed
/// `URLProtocol` — no real network traffic (#79).
final class GeminiClientTests: LLMClientTestCase {
    private var sut: GeminiClient!

    override func setUp() async throws {
        try await super.setUp()
        sut = GeminiClient(session: session)
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    private func stream() async throws -> AsyncThrowingStream<String, Error> {
        try await sut.streamAnalysis(systemPrompt: "You are FitBuddy.", userPrompt: "Analyze my week.", apiKey: "AIza-test")
    }

    // MARK: - Request shape

    func testRequestTargetsTheStreamingEndpointWithSSEEnabled() async throws {
        stub(body: GeminiSSEFactory.body(textChunks: ["Hi"]))

        _ = try await collect(try await stream())

        let request = try capturedRequest()
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiClient.model):streamGenerateContent?alt=sse"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
    }

    /// Regression guard for the rule in `GeminiClient`: Google's own examples
    /// pass the key as `?key=`, which would put it in every log line and
    /// redirect target that touches the URL.
    func testSendsTheKeyAsAHeaderAndNeverInTheURL() async throws {
        stub(body: GeminiSSEFactory.body(textChunks: ["Hi"]))

        _ = try await collect(try await stream())

        let request = try capturedRequest()
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "AIza-test")
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertFalse(url.contains("AIza-test"), "the API key must never appear in the URL")
        XCTAssertFalse(url.contains("key="), "the key query parameter must not be used")
    }

    func testBodyCarriesTheSystemInstructionSeparatelyFromTheUserTurn() async throws {
        stub(body: GeminiSSEFactory.body(textChunks: ["Hi"]))

        _ = try await collect(try await stream())

        let json = try jsonBody(of: try capturedRequest())
        let system = try XCTUnwrap(json["systemInstruction"] as? [String: Any])
        let systemParts = try XCTUnwrap(system["parts"] as? [[String: Any]])
        XCTAssertEqual(systemParts.first?["text"] as? String, "You are FitBuddy.")

        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(contents.first?["role"] as? String, "user")
        let userParts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(userParts.first?["text"] as? String, "Analyze my week.")

        let config = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertEqual(config["maxOutputTokens"] as? Int, GeminiClient.maxOutputTokens)
    }

    func testReportsItsProvider() {
        XCTAssertEqual(sut.provider, .gemini)
    }

    // MARK: - Stream parsing

    func testStreamsIncrementalTextChunks() async throws {
        stub(body: GeminiSSEFactory.body(textChunks: ["Increase ", "squat ", "by 2.5 kg."]))

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, ["Increase ", "squat ", "by 2.5 kg."])
    }

    func testIgnoresChunksThatCarryNoText() async throws {
        // Gemini sends candidates with only a `finishReason` or usage metadata;
        // yielding "" for those would make an empty answer look like a real one.
        stub(body: GeminiSSEFactory.metadataOnlyBody())

        let chunks = try await collect(try await stream())

        XCTAssertEqual(chunks, [])
    }

    // MARK: - Rejection before acceptance

    /// Google answers a rejected API key with 403, not 401 — it has to land in
    /// the same bucket, or a bad Gemini key would read as "unexpected response".
    func testForbiddenMapsToUnauthorized() async throws {
        stub(statusCode: 403)

        do {
            _ = try await stream()
            XCTFail("expected unauthorized")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testServiceUnavailableOnServerError() async throws {
        stub(statusCode: 500)

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
}
