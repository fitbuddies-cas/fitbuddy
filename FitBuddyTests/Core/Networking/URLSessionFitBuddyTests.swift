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

    func testStreamingSessionKeepsTheSamePrivacyGuarantees() {
        let configuration = URLSession.fitBuddyStreaming.configuration

        XCTAssertNil(configuration.urlCache, "Responses must not be cached to disk")
        XCTAssertNil(configuration.httpCookieStorage, "Cookies must not be persisted")
        XCTAssertNil(configuration.urlCredentialStorage, "Credentials must not be persisted")
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    /// The LLM session's timeout is an *idle* timeout, and a reasoning model
    /// sends nothing at all until its first token — so this window has to
    /// outlast the thinking phase, not just a stalled transfer. At the 30s of
    /// `AnalysisViewModel.defaultSlowThreshold` a provider that thought a
    /// little longer than usual was cut off as a network failure and silently
    /// handed over to the next one.
    func testStreamingSessionOutwaitsTheCancelOffer() {
        let timeout = URLSession.fitBuddyStreaming.configuration.timeoutIntervalForRequest

        XCTAssertGreaterThan(
            timeout,
            30,
            "the transport must not give up while the user is still being offered the choice to wait"
        )
        XCTAssertGreaterThan(timeout, URLSession.fitBuddy.configuration.timeoutIntervalForRequest)
    }

    func testSessionIsNotTheSharedSession() {
        // `.shared` caches to disk by default — a regression to it would
        // silently undo the guarantees asserted above.
        XCTAssertFalse(URLSession.fitBuddy === URLSession.shared)
    }
}
