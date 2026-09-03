import XCTest
@testable import FitBuddy

/// Guards the privacy guarantees of the shared API session (#24): no part of a
/// key-bearing request or its response may be persisted to disk.
final class URLSessionFitBuddyTests: XCTestCase {
    func testSessionUsesEphemeralConfiguration() {
        let configuration = URLSession.fitBuddy.configuration

        XCTAssertNil(configuration.urlCache, "Responses must not be cached to disk")
        XCTAssertNil(configuration.httpCookieStorage, "Cookies must not be persisted")
        XCTAssertNil(configuration.urlCredentialStorage, "Credentials must not be persisted")
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testSessionIsNotTheSharedSession() {
        // `.shared` caches to disk by default — a regression to it would
        // silently undo the guarantees asserted above.
        XCTAssertFalse(URLSession.fitBuddy === URLSession.shared)
    }
}
