import XCTest
@testable import FitBuddy

/// Unit tests for `SyncFailure` (issue #28): the mapping that keeps a network
/// failure distinguishable from an HTTP failure in the banner.
final class SyncFailureTests: XCTestCase {
    func testNetworkFailureMapsToOffline() {
        XCTAssertEqual(SyncFailure(syncError: WorkoutSyncError.networkUnavailable), .offline)
    }

    /// A failed certificate check (pinning, #153) gets its own reason: the
    /// banner must not say "no connection" when the connection could not be
    /// verified.
    func testUntrustedConnectionKeepsItsOwnReason() {
        XCTAssertEqual(SyncFailure(syncError: WorkoutSyncError.untrustedConnection), .untrustedConnection)
        XCTAssertEqual(WorkoutSyncError(connectorError: .untrustedConnection), .untrustedConnection)
        XCTAssertNotEqual(SyncFailure.untrustedConnection.summary, SyncFailure.offline.summary)
        XCTAssertEqual(SyncFailure.untrustedConnection.summary, "connection not trusted")
    }

    func testServerFailuresStaySeparateFromTheNetworkCase() {
        XCTAssertEqual(SyncFailure(syncError: WorkoutSyncError.serviceUnavailable), .serviceUnavailable)
        XCTAssertEqual(
            SyncFailure(syncError: WorkoutSyncError.rateLimited(retryAfter: 30)),
            .rateLimited(retryAfter: 30)
        )
        XCTAssertEqual(SyncFailure(syncError: WorkoutSyncError.invalidResponse), .unreadableResponse)
    }

    func testLocalFailuresKeepTheirOwnReason() {
        XCTAssertEqual(SyncFailure(syncError: WorkoutSyncError.keychainUnavailable), .keychainUnavailable)
        XCTAssertEqual(SyncFailure(syncError: WorkoutSyncError.persistenceFailed), .cacheWriteFailed)
    }

    /// The auth failures are not banner material — they route to onboarding.
    func testAuthFailuresProduceNoBannerReason() {
        XCTAssertNil(SyncFailure(syncError: WorkoutSyncError.unauthorized))
        XCTAssertNil(SyncFailure(syncError: WorkoutSyncError.missingAPIKey))
    }

    /// A source that cannot sync yet is nothing the user can act on — it gets
    /// the generic banner rather than a reason of its own.
    func testANotImplementedSourceFallsBackToTheGenericReason() {
        XCTAssertEqual(SyncFailure(syncError: WorkoutSyncError.notImplemented), .unknown)
    }

    func testUnknownErrorsStillProduceABanner() {
        struct Boom: Error {}
        XCTAssertEqual(SyncFailure(syncError: Boom()), .unknown)
    }

    /// Every reason needs copy — an empty summary would render "Last synced
    /// 2 h ago · " with a dangling separator.
    func testEverySummaryIsNonEmpty() {
        for failure in Self.allFailures {
            XCTAssertFalse(failure.summary.isEmpty, "\(failure) has no summary")
        }
    }

    // MARK: - Retry-After

    /// Hevy's `Retry-After` is the only part of a rate limit the user can act
    /// on; carrying it as far as the banner and then not saying it wastes it.
    func testRateLimitSpellsOutTheWaitHevySent() {
        XCTAssertEqual(
            SyncFailure.rateLimited(retryAfter: 30).summary,
            "too many requests, retry in 30 s"
        )
        XCTAssertEqual(
            SyncFailure.rateLimited(retryAfter: 180).summary,
            "too many requests, retry in 3 min"
        )
    }

    /// Without a usable value the clause is dropped rather than printed as
    /// "retry in 0 s", which would send the user straight back into the limit.
    func testRateLimitWithoutARetryAfterDropsTheClause() {
        XCTAssertEqual(SyncFailure.rateLimited(retryAfter: nil).summary, "too many requests")
        XCTAssertEqual(SyncFailure.rateLimited(retryAfter: 0).summary, "too many requests")
    }

    // MARK: - Refresh toast (#43)

    /// The toast after a failed pull is a whole sentence on its own, not the
    /// banner fragment — "sync failed" as a standalone message says nothing.
    func testEveryFailureHasAStandaloneRefreshMessage() {
        for failure in Self.allFailures {
            let message = failure.refreshMessage
            XCTAssertFalse(message.isEmpty, "\(failure) has no refresh message")
            XCTAssertTrue(message.hasSuffix("."), "\(failure) is not a sentence: \(message)")
            XCTAssertNotEqual(message, failure.summary, "\(failure) just reuses the banner fragment")
        }
    }

    /// The wait Hevy sent is the one thing that makes the message actionable,
    /// so it survives into the toast too.
    func testRateLimitedRefreshMessageNamesTheWait() {
        XCTAssertEqual(
            SyncFailure.rateLimited(retryAfter: 180).refreshMessage,
            "Too many requests to Hevy. Try again in 3 min."
        )
        XCTAssertEqual(
            SyncFailure.rateLimited(retryAfter: nil).refreshMessage,
            "Too many requests to Hevy. Try again in a moment."
        )
    }

    // MARK: - Symbols

    func testEveryFailureHasASymbol() {
        for failure in Self.allFailures {
            XCTAssertFalse(failure.symbolName.isEmpty, "\(failure) has no symbol")
        }
    }

    /// The offline glyph is the one a user reads as "check your reception".
    /// Putting it next to a locked Keychain or a full disk sends them looking
    /// in the wrong place, and the icon is read before the text.
    func testOnlyTheNetworkFailureUsesTheOfflineGlyph() {
        let offline = SyncFailure.offline.symbolName

        for failure in Self.allFailures where failure != .offline {
            XCTAssertNotEqual(failure.symbolName, offline, "\(failure) claims to be a network problem")
        }
    }

    private static let allFailures: [SyncFailure] = [
        .offline, .untrustedConnection, .serviceUnavailable, .rateLimited(retryAfter: nil),
        .keychainUnavailable, .unreadableResponse, .cacheWriteFailed, .unknown,
    ]
}
