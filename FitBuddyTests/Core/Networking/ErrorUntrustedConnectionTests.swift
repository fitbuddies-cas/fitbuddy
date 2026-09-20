import XCTest
@testable import FitBuddy

/// Unit tests for `Error.isUntrustedConnection` (#153): the one predicate
/// every transport site uses to tell a failed certificate check apart from
/// an unreachable host.
final class ErrorUntrustedConnectionTests: XCTestCase {
    func testCertificateFailuresAreUntrusted() {
        let codes: [URLError.Code] = [
            .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
            .serverCertificateHasBadDate, .serverCertificateNotYetValid, .secureConnectionFailed,
        ]
        for code in codes {
            XCTAssertTrue(URLError(code).isUntrustedConnection, "\(code)")
        }
    }

    /// Being offline is the case the predicate must never swallow — the
    /// user would be told to switch networks when they have none.
    func testConnectivityFailuresAreNotUntrusted() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost,
            .networkConnectionLost, .dnsLookupFailed, .cancelled,
        ]
        for code in codes {
            XCTAssertFalse(URLError(code).isUntrustedConnection, "\(code)")
        }
    }

    func testNonURLErrorsAreNotUntrusted() {
        struct Boom: Error {}
        XCTAssertFalse(Boom().isUntrustedConnection)
        XCTAssertFalse(CancellationError().isUntrustedConnection)
    }
}
