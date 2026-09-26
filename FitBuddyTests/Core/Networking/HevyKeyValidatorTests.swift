import XCTest
@testable import FitBuddy

/// Unit tests for `HevyKeyValidator` using a stubbed `URLProtocol` — no real
/// network traffic.
final class HevyKeyValidatorTests: XCTestCase {
    private var sut: HevyKeyValidator!

    override func setUp() {
        super.setUp()
        sut = HevyKeyValidator(session: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        sut = nil
        super.tearDown()
    }

    private static func response(status: Int, for request: URLRequest) -> (HTTPURLResponse, Data) {
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (http, Data())
    }

    func testSendsKeyInAPIKeyHeaderToWorkoutsEndpoint() async throws {
        nonisolated(unsafe) var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return Self.response(status: 200, for: request)
        }

        try await sut.validate("hv_live_abc")

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "hv_live_abc")
        XCTAssertEqual(request.url?.host, "api.hevyapp.com")
        XCTAssertEqual(request.url?.path, "/v1/workouts")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testHTTP200Succeeds() async throws {
        StubURLProtocol.handler = { Self.response(status: 200, for: $0) }
        try await sut.validate("hv_live_abc")
    }

    func testHTTP401ThrowsInvalidKey() async {
        StubURLProtocol.handler = { Self.response(status: 401, for: $0) }
        await assertValidateThrows("hv_live_bad", expected: .invalidKey)
    }

    func testHTTP403ThrowsUnexpectedStatusNotInvalidKey() async {
        StubURLProtocol.handler = { Self.response(status: 403, for: $0) }
        await assertValidateThrows("hv_live_bad", expected: .unexpectedStatus(403))
    }

    func testHTTP500ThrowsUnexpectedStatus() async {
        StubURLProtocol.handler = { Self.response(status: 500, for: $0) }
        await assertValidateThrows("hv_live_abc", expected: .unexpectedStatus(500))
    }

    func testConnectionFailureThrowsTransport() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        await assertValidateThrows("hv_live_abc", expected: .transport)
    }

    /// A failed certificate check (pinning, #153) must not read as offline.
    func testCertificateFailureThrowsUntrustedConnection() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.serverCertificateUntrusted)
        }
        await assertValidateThrows("hv_live_abc", expected: .untrustedConnection)
    }

    private func assertValidateThrows(
        _ key: String,
        expected: HevyKeyValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await sut.validate(key)
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as HevyKeyValidationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
