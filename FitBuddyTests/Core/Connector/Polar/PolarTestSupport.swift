import XCTest
@testable import FitBuddy

/// Shared helpers for the Polar connector tests.
enum PolarTestSupport {
    /// Reads a request body whether `URLSession` left it on `httpBody` or
    /// handed it over as a stream (which it does for the OAuth form posts).
    static func body(of request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(decoding: body, as: UTF8.self)
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func http(_ status: Int, for request: URLRequest, body: String = "") -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(body.utf8))
    }
}

extension XCTestCase {
    /// Fails unless `expression` throws `expected` (a `ConnectorError`).
    func assertThrowsConnectorError<T>(
        _ expected: ConnectorError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () async throws -> T
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as ConnectorError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
