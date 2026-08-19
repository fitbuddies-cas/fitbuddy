import XCTest
@testable import FitBuddy

/// Unit tests for `SyncFailure` (issue #28): the mapping that keeps a network
/// failure distinguishable from an HTTP failure in the banner.
final class SyncFailureTests: XCTestCase {
    func testNetworkFailureMapsToOffline() {
        XCTAssertEqual(SyncFailure(syncError: HevyServiceError.networkUnavailable), .offline)
    }

    func testServerFailuresStaySeparateFromTheNetworkCase() {
        XCTAssertEqual(SyncFailure(syncError: HevyServiceError.serviceUnavailable), .serviceUnavailable)
        XCTAssertEqual(
            SyncFailure(syncError: HevyServiceError.rateLimited(retryAfter: 30)),
            .rateLimited(retryAfter: 30)
        )
        XCTAssertEqual(SyncFailure(syncError: HevyServiceError.unexpectedStatus(403)), .unreadableResponse)
        XCTAssertEqual(SyncFailure(syncError: HevyServiceError.invalidResponse), .unreadableResponse)
    }

    func testLocalFailuresKeepTheirOwnReason() {
        XCTAssertEqual(SyncFailure(syncError: HevyServiceError.keychainUnavailable), .keychainUnavailable)
        XCTAssertEqual(SyncFailure(syncError: HevyServiceError.persistenceFailed), .cacheWriteFailed)
    }

    /// The auth failures are not banner material — they route to onboarding.
    func testAuthFailuresProduceNoBannerReason() {
        XCTAssertNil(SyncFailure(syncError: HevyServiceError.unauthorized))
        XCTAssertNil(SyncFailure(syncError: HevyServiceError.missingAPIKey))
    }

    func testUnknownErrorsStillProduceABanner() {
        struct Boom: Error {}
        XCTAssertEqual(SyncFailure(syncError: Boom()), .unknown)
    }

    /// Every reason needs copy — an empty summary would render "Last synced
    /// 2 h ago · " with a dangling separator.
    func testEverySummaryIsNonEmpty() {
        let failures: [SyncFailure] = [
            .offline, .serviceUnavailable, .rateLimited(retryAfter: nil),
            .keychainUnavailable, .unreadableResponse, .cacheWriteFailed, .unknown,
        ]
        for failure in failures {
            XCTAssertFalse(failure.summary.isEmpty, "\(failure) has no summary")
        }
    }
}
