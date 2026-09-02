import Foundation
import XCTest
@testable import FitBuddy

/// Shared scaffolding for the three `LLMProviderClient` test cases: stub the
/// one endpoint under test, capture the request that reached it, and read the
/// answer back.
///
/// A base class rather than free functions so `captured` can be per-test
/// instance state; `StubURLProtocol.handler` is process-wide, and each subclass
/// clears it in `tearDown`.
class LLMClientTestCase: XCTestCase {
    /// Last request the stub answered.
    nonisolated(unsafe) private static var captured: URLRequest?

    var session: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        Self.captured = nil
        session = StubURLProtocol.makeSession()
    }

    override func tearDown() async throws {
        StubURLProtocol.handler = nil
        Self.captured = nil
        session = nil
        try await super.tearDown()
    }

    /// The request the client actually sent, or a failure if it sent none.
    func capturedRequest(file: StaticString = #filePath, line: UInt = #line) throws -> URLRequest {
        try XCTUnwrap(Self.captured, "the client sent no request", file: file, line: line)
    }

    func stub(statusCode: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        StubURLProtocol.handler = { request in
            Self.captured = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
            return (response, body)
        }
    }

    func stubTransportFailure() {
        struct TransportFailure: Error {}
        StubURLProtocol.handler = { request in
            Self.captured = request
            throw TransportFailure()
        }
    }

    func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var chunks: [String] = []
        for try await chunk in stream { chunks.append(chunk) }
        return chunks
    }

    /// The JSON body the client sent.
    ///
    /// `URLProtocol`-backed sessions sometimes hand the body over as a stream
    /// rather than `httpBody` — read whichever is populated.
    func jsonBody(of request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                collected.append(buffer, count: read)
            }
            data = collected
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
