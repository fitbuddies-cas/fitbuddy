import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for `HevyService` using a stubbed `URLProtocol` — no real network
/// traffic. Keychain access uses the real `KeychainService` on the simulator;
/// SwiftData runs in-memory and the sync timestamp lives in an isolated
/// `UserDefaults` suite.
final class HevyServiceTests: XCTestCase {
    /// Fixed clock so window boundaries are deterministic.
    private static let now = Date(timeIntervalSince1970: 1_754_400_000) // 2025-08-05 14:40 UTC

    private var keychain: KeychainService!
    private var container: ModelContainer!
    private var workouts: WorkoutStore!
    private var timestamps: SyncTimestampStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: HevyService!

    /// Requests the stub answered, in order.
    nonisolated(unsafe) private static var captured: [URLRequest] = []

    override func setUp() async throws {
        try await super.setUp()
        Self.captured = []
        keychain = KeychainService()
        try await keychain.delete(.hevyAPIKey)
        try await keychain.save("hv_live_abc", for: .hevyAPIKey)

        container = try ModelContainerFactory.makeInMemory()
        workouts = WorkoutStore(modelContainer: container)
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        timestamps = SyncTimestampStore(defaults: defaults)
        sut = makeService()
    }

    override func tearDown() async throws {
        StubURLProtocol.handler = nil
        Self.captured = []
        Self.pendingPages = []
        try await keychain.delete(.hevyAPIKey)
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        timestamps = nil
        workouts = nil
        container = nil
        defaults = nil
        keychain = nil
        try await super.tearDown()
    }

    private func makeService() -> HevyService {
        // UTC so the day-aligned window start does not depend on the machine's
        // time zone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        return HevyService(
            session: StubURLProtocol.makeSession(),
            keychain: keychain,
            workouts: workouts,
            timestamps: timestamps,
            sessionReset: SessionResetService(
                keychain: keychain,
                workouts: workouts,
                results: AnalysisResultStore(modelContainer: workouts.modelContainer),
                timestamps: timestamps
            ),
            calendar: calendar,
            now: { Self.now }
        )
    }

    // MARK: - Request shape

    func testRequestsWorkoutsWithKeyAndMaximumPageSize() async throws {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [])])

        _ = try await sut.syncRecentWorkouts()

        let request = try XCTUnwrap(Self.captured.first)
        XCTAssertEqual(Self.captured.count, 1)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "hv_live_abc")
        XCTAssertEqual(request.url?.host, "api.hevyapp.com")
        XCTAssertEqual(request.url?.path, "/v1/workouts")
        XCTAssertEqual(Self.queryValue("page", in: request), "1")
        XCTAssertEqual(Self.queryValue("pageSize", in: request), "10")
    }

    // MARK: - Pagination (#25 AC1)

    func testWalksEveryPageUntilPageCountIsReached() async throws {
        stub(pages: (1...3).map { page in
            HevyPayloadFactory.page(
                page: page,
                pageCount: 3,
                workouts: [
                    HevyPayloadFactory.workout(id: "w-\(page)a", start: daysAgo(page)),
                    HevyPayloadFactory.workout(id: "w-\(page)b", start: daysAgo(page)),
                ]
            )
        })

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.workoutCount, 6)
        XCTAssertEqual(Self.captured.compactMap { Self.queryValue("page", in: $0) }, ["1", "2", "3"])
        let cached = try await workouts.workoutCount()
        XCTAssertEqual(cached, 6)
    }

    func testStopsPaginatingAtTheFirstPageEntirelyOutsideTheWindow() async throws {
        stub(pages: [
            HevyPayloadFactory.page(page: 1, pageCount: 9, workouts: [
                HevyPayloadFactory.workout(id: "recent", start: daysAgo(3)),
            ]),
            HevyPayloadFactory.page(page: 2, pageCount: 9, workouts: [
                HevyPayloadFactory.workout(id: "ancient", start: daysAgo(400)),
            ]),
            // Pages 3–9 exist but must never be requested.
            HevyPayloadFactory.page(page: 3, pageCount: 9, workouts: [
                HevyPayloadFactory.workout(id: "even-older", start: daysAgo(500)),
            ]),
        ])

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.workoutCount, 1)
        XCTAssertEqual(Self.captured.count, 2, "Walk must stop once a page falls outside the window")
        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["recent"])
    }

    func testStopsAtAPageThatComesBackEmptyEvenWhenPageCountClaimsMore() async throws {
        // A page with no workouts at all has nothing behind it. `page_count` is
        // decoded leniently, so trusting it here would send up to `maxPages`
        // requests on the user's key that all return nothing — and the empty
        // result would then wipe the cache as a "successful" sync.
        stub(pages: [
            HevyPayloadFactory.page(page: 1, pageCount: 40, workouts: []),
            HevyPayloadFactory.page(page: 2, pageCount: 40, workouts: [
                HevyPayloadFactory.workout(id: "unreachable", start: daysAgo(1)),
            ]),
        ])

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.workoutCount, 0)
        XCTAssertEqual(Self.captured.count, 1, "An empty page must end the walk")
    }

    func testKeepsOnlyWorkoutsInsideTheNinetyDayWindow() async throws {
        stub(pages: [
            HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
                HevyPayloadFactory.workout(id: "today", start: daysAgo(0)),
                HevyPayloadFactory.workout(id: "day-89", start: daysAgo(89)),
                HevyPayloadFactory.workout(id: "day-95", start: daysAgo(95)),
            ]),
        ])

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.workoutCount, 2)
        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["today", "day-89"])
    }

    func testWindowStartIsMidnightNinetyDaysBack() async throws {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [])])

        let result = try await sut.syncRecentWorkouts()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let expected = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: Self.now))
        XCTAssertEqual(result.windowStart, expected)
    }

    func testWorkoutRepeatedAcrossAPageBoundaryIsCachedOnce() async throws {
        // Hevy paginates newest first over a live list: a workout logged while
        // the walk is between two pages pushes "boundary" down a slot, so it
        // comes back on page 2 as well.
        stub(pages: [
            HevyPayloadFactory.page(page: 1, pageCount: 2, workouts: [
                HevyPayloadFactory.workout(id: "newest", start: daysAgo(1)),
                HevyPayloadFactory.workout(id: "boundary", start: daysAgo(2)),
            ]),
            HevyPayloadFactory.page(page: 2, pageCount: 2, workouts: [
                HevyPayloadFactory.workout(id: "boundary", start: daysAgo(2)),
                HevyPayloadFactory.workout(id: "oldest", start: daysAgo(3)),
            ]),
        ])

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.workoutCount, 3, "A duplicate would inflate every derived metric")
        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["newest", "boundary", "oldest"])
    }

    func testEmptyHistoryCachesNothing() async throws {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [])])

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.workoutCount, 0)
        let cached = try await workouts.workoutCount()
        XCTAssertEqual(cached, 0)
    }

    // MARK: - Cache replacement

    func testResyncReplacesThePreviousWindow() async throws {
        stub(pages: [
            HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
                HevyPayloadFactory.workout(id: "w-1", start: daysAgo(2)),
                HevyPayloadFactory.workout(id: "w-2", start: daysAgo(1)),
            ]),
        ])
        _ = try await sut.syncRecentWorkouts()

        // w-1 was deleted in Hevy, w-3 was added.
        stub(pages: [
            HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
                HevyPayloadFactory.workout(id: "w-2", start: daysAgo(1)),
                HevyPayloadFactory.workout(id: "w-3", start: daysAgo(0)),
            ]),
        ])
        _ = try await sut.syncRecentWorkouts()

        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(Set(ids), ["w-2", "w-3"])
    }

    // MARK: - Sync timestamp (#25 AC3)

    func testSuccessfulSyncUpdatesLastSyncTimestamp() async throws {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
            HevyPayloadFactory.workout(id: "w-1", start: daysAgo(1)),
        ])])

        let result = try await sut.syncRecentWorkouts()

        let stored = await timestamps.lastSync()
        XCTAssertEqual(stored, Self.now)
        XCTAssertEqual(result.syncedAt, Self.now)
    }

    func testFailedSyncLeavesLastSyncTimestampUntouched() async throws {
        let previous = Date(timeIntervalSince1970: 1_750_000_000)
        await timestamps.setLastSync(previous)
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        await assertSyncThrows(.networkUnavailable)

        let stored = await timestamps.lastSync()
        XCTAssertEqual(stored, previous)
    }

    func testFailedSyncKeepsCachedWorkouts() async throws {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
            HevyPayloadFactory.workout(id: "w-1", start: daysAgo(1)),
        ])])
        _ = try await sut.syncRecentWorkouts()

        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        await assertSyncThrows(.networkUnavailable)

        // US-2 AC2: cached data must survive an unreachable API.
        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["w-1"])
    }

    // MARK: - HTTP 401 → hard logout (US-1 AC3)

    func testUnauthorizedDeletesKeyAndCacheAndThrows() async throws {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
            HevyPayloadFactory.workout(id: "w-1", start: daysAgo(1)),
        ])])
        _ = try await sut.syncRecentWorkouts()

        StubURLProtocol.handler = { Self.response(status: 401, for: $0) }
        await assertSyncThrows(.unauthorized)

        let storedKey = try await keychain.read(.hevyAPIKey)
        XCTAssertNil(storedKey, "Revoked key must be removed from the Keychain")
        let cached = try await workouts.workoutCount()
        XCTAssertEqual(cached, 0, "Stale data must not survive a hard logout")
        let lastSync = await timestamps.lastSync()
        XCTAssertNil(lastSync)
    }

    func testSyncWithoutStoredKeyThrowsMissingAPIKey() async throws {
        try await keychain.delete(.hevyAPIKey)
        StubURLProtocol.handler = { Self.response(status: 200, for: $0) }

        await assertSyncThrows(.missingAPIKey)
        XCTAssertTrue(Self.captured.isEmpty, "No request may be sent without a key")
    }

    // MARK: - Other error mapping

    func testRateLimitedCarriesRetryAfter() async {
        StubURLProtocol.handler = { Self.response(status: 429, for: $0, headers: ["Retry-After": "30"]) }
        await assertSyncThrows(.rateLimited(retryAfter: 30))
    }

    func testRateLimitedWithoutRetryAfterHeader() async {
        StubURLProtocol.handler = { Self.response(status: 429, for: $0) }
        await assertSyncThrows(.rateLimited(retryAfter: nil))
    }

    func testServerErrorMapsToServiceUnavailable() async {
        StubURLProtocol.handler = { Self.response(status: 503, for: $0) }
        await assertSyncThrows(.serviceUnavailable)
    }

    func testForbiddenDoesNotTriggerLogout() async throws {
        StubURLProtocol.handler = { Self.response(status: 403, for: $0) }

        await assertSyncThrows(.unexpectedStatus(403))

        // 403 can hit a valid key (WAF, geo) — wiping it would be wrong.
        let storedKey = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(storedKey, "hv_live_abc")
    }

    func testCancellationIsNotReportedAsANetworkFailure() async {
        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }

        do {
            _ = try await sut.syncRecentWorkouts()
            XCTFail("Expected the cancellation to propagate")
        } catch let error as URLError {
            // Navigating away mid-sync must not surface as "no internet".
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedBodyMapsToInvalidResponse() async {
        StubURLProtocol.handler = { request in
            (Self.http(status: 200, for: request, headers: nil), Data("not json".utf8))
        }
        await assertSyncThrows(.invalidResponse)
    }

    // MARK: - Helpers

    /// Page bodies the stub still has to hand out, in order.
    nonisolated(unsafe) private static var pendingPages: [Data] = []

    /// Answers requests with `pages` in order; the last page repeats if the
    /// service asks for more, so an over-eager walk shows up as an extra
    /// captured request rather than as a stub failure.
    private func stub(pages: [Data]) {
        Self.captured = []
        Self.pendingPages = pages
        StubURLProtocol.handler = { request in
            Self.captured.append(request)
            let body = Self.pendingPages.count > 1
                ? Self.pendingPages.removeFirst()
                : (Self.pendingPages.first ?? Data())
            return (Self.http(status: 200, for: request, headers: nil), body)
        }
    }

    private static func response(
        status: Int,
        for request: URLRequest,
        headers: [String: String]? = nil
    ) -> (HTTPURLResponse, Data) {
        captured.append(request)
        return (http(status: status, for: request, headers: headers), Data())
    }

    private static func http(
        status: Int,
        for request: URLRequest,
        headers: [String: String]?
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    private static func queryValue(_ name: String, in request: URLRequest) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first { $0.name == name }?.value
    }

    /// `days` before the fixed clock.
    private func daysAgo(_ days: Int) -> Date {
        Self.now.addingTimeInterval(-Double(days) * 24 * 3600)
    }

    private func assertSyncThrows(
        _ expected: HevyServiceError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await sut.syncRecentWorkouts()
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as HevyServiceError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
