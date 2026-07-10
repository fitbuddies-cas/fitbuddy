import Foundation
import XCTest

/// `URLProtocol` stub for exercising `URLSession`-based services without
/// network access. Configure `handler` per test; every request routed through
/// a session using this protocol is answered by it.
final class StubURLProtocol: URLProtocol {
    /// Maps an intercepted request to a response + body, or throws to simulate
    /// a transport failure. Set per test; nonisolated(unsafe) is acceptable
    /// because XCTest runs these tests serially.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Returns an ephemeral session whose requests are all served by this stub.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("StubURLProtocol.handler not set")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
