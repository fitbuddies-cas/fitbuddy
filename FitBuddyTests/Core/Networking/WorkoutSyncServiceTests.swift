import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for `WorkoutSyncService` driving a real `HevyConnector` over a
/// stubbed `URLProtocol` — no real network traffic. The pair is tested
/// together because the sync is only correct if what the connector returns
/// reaches the cache: Keychain access uses the real `KeychainService` on the
/// simulator, SwiftData runs in-memory and the sync timestamp lives in an
/// isolated `UserDefaults` suite.
///
/// Since #143 the connectors come out of a `ConnectorRegistry`. The Hevy-only
/// tests register just Hevy and leave Strava unconfigured, so they describe
/// the same behaviour they always did; the fan-out section registers both.
final class WorkoutSyncServiceTests: XCTestCase {
    /// Fixed clock so window boundaries are deterministic.
    private static let now = Date(timeIntervalSince1970: 1_754_400_000) // 2025-08-05 14:40 UTC

    private var keychain: KeychainService!
    private var container: ModelContainer!
    private var workouts: WorkoutStore!
    private var timestamps: SyncTimestampStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var registry: ConnectorRegistry!
    private var stravaStore: StubStravaCredentialStore!
    private var polarStore: StubPolarCredentialStore!
    private var sut: WorkoutSyncService!

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
        registry = ConnectorRegistry()
        stravaStore = StubStravaCredentialStore()
        polarStore = StubPolarCredentialStore()
        sut = await makeService()
    }

    override func tearDown() async throws {
        StubURLProtocol.handler = nil
        Self.captured = []
        Self.pendingPages = []
        try await keychain.delete(.hevyAPIKey)
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        stravaStore = nil
        polarStore = nil
        registry = nil
        timestamps = nil
        workouts = nil
        container = nil
        defaults = nil
        keychain = nil
        try await super.tearDown()
    }

    /// The same service against a different Hevy data source, so the tests
    /// can separate "the sync orchestrates correctly" from "the Hevy connector
    /// parses correctly".
    private func makeService(connector: any FitnessConnector) async -> WorkoutSyncService {
        await registry.register(connector, for: .hevy)
        return WorkoutSyncService(
            registry: registry,
            keychain: keychain,
            stravaCredentials: stravaStore,
            polarCredentials: polarStore,
            workouts: workouts,
            timestamps: timestamps,
            sessionReset: SessionResetService(
                keychain: keychain,
                workouts: workouts,
                results: AnalysisResultStore(modelContainer: workouts.modelContainer),
                timestamps: timestamps
            ),
            calendar: Self.utcCalendar,
            now: { Self.now }
        )
    }

    private static var utcCalendar: Calendar {
        // UTC so the day-aligned window start does not depend on the machine's
        // time zone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func makeService() async -> WorkoutSyncService {
        await makeService(connector: HevyConnector(session: StubURLProtocol.makeSession()))
    }

    private static var stravaPair: ConnectorCredentials {
        .oauth(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: now.addingTimeInterval(4 * 3600))
    }

    /// Connects Strava: a stored pair plus a registered connector.
    private func connectStrava(_ connector: any FitnessConnector) async {
        stravaStore = StubStravaCredentialStore(
            clientCredentials: StravaClientCredentials(clientID: "123456", clientSecret: "s3cr3t"),
            credentials: Self.stravaPair
        )
        await registry.register(connector, for: .strava)
    }

    private static var polarPair: ConnectorCredentials {
        .oauth(accessToken: "polar-access-1", refreshToken: "polar-refresh-1", expiresAt: now.addingTimeInterval(4 * 3600))
    }

    /// Connects Polar: a stored pair plus a registered connector (#159).
    private func connectPolar(_ connector: any FitnessConnector) async {
        polarStore = StubPolarCredentialStore(credentials: Self.polarPair)
        await registry.register(connector, for: .polar)
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

    /// 403 is reported as an unreadable response, not as an auth failure:
    /// `ConnectorError` has no "odd status" case, and the distinction that
    /// matters here is that the key survives.
    func testForbiddenDoesNotTriggerLogout() async throws {
        StubURLProtocol.handler = { Self.response(status: 403, for: $0) }

        await assertSyncThrows(.invalidResponse)

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

    // MARK: - Source independence (ADR-6, #34)

    /// The payoff of the refactor: the sync names no provider. Everything it
    /// caches comes out of a `FitnessConnector`, so a second source (#35) is a
    /// different argument here, not a different sync.
    func testCachesWhatAnyConnectorReturns() async throws {
        let connector = MockConnector()
        await connector.setFetchActivitiesResult(.success([
            ActivityFactory.activity(id: "a-1", start: daysAgo(1)),
            ActivityFactory.activity(id: "a-2", start: daysAgo(2)),
        ]))
        let sut = await makeService(connector: connector)

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.workoutCount, 2)
        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["a-1", "a-2"])
    }

    /// The window boundary belongs to the app, not to the provider: the
    /// connector is told where the 90 days start and filters against it.
    func testAsksTheConnectorForTheNinetyDayWindow() async throws {
        let connector = MockConnector()
        let sut = await makeService(connector: connector)

        let result = try await sut.syncRecentWorkouts()

        let since = await connector.lastFetchSince
        XCTAssertEqual(since, result.windowStart)
    }

    func testTheStoredKeyIsHandedToTheConnector() async throws {
        let connector = MockConnector()
        let sut = await makeService(connector: connector)

        _ = try await sut.syncRecentWorkouts()

        let credentials = await connector.lastConnectedCredentials
        XCTAssertEqual(credentials, .apiKey("hv_live_abc"))
    }

    /// A rejected key is the connector's finding but the app's problem: the
    /// hard logout and the in-memory credentials are cleared here, above the
    /// connector, because neither belongs to the provider.
    func testConnectorUnauthorizedRunsTheHardLogoutAndDisconnects() async throws {
        let connector = MockConnector()
        await connector.setFetchActivitiesResult(.failure(.unauthorized))
        let sut = await makeService(connector: connector)

        do {
            _ = try await sut.syncRecentWorkouts()
            XCTFail("Expected .unauthorized to be thrown")
        } catch {
            XCTAssertEqual(error as? WorkoutSyncError, .unauthorized)
        }

        let didDisconnect = await connector.didDisconnect
        XCTAssertTrue(didDisconnect)
        let storedKey = try await keychain.read(.hevyAPIKey)
        XCTAssertNil(storedKey, "Revoked key must be removed from the Keychain")
    }

    /// Every other connector failure is reported as-is — no logout, no cache
    /// change: the dashboard keeps showing what it has (US-2 AC2).
    func testOtherConnectorFailuresLeaveTheSessionAlone() async throws {
        let connector = MockConnector()
        await connector.setFetchActivitiesResult(.failure(.rateLimited(retryAfter: 30)))
        let sut = await makeService(connector: connector)

        do {
            _ = try await sut.syncRecentWorkouts()
            XCTFail("Expected .rateLimited to be thrown")
        } catch {
            XCTAssertEqual(error as? WorkoutSyncError, .rateLimited(retryAfter: 30))
        }

        let didDisconnect = await connector.didDisconnect
        XCTAssertFalse(didDisconnect)
        let storedKey = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(storedKey, "hv_live_abc")
    }

    /// "Delete all data" and the settings logout both wipe the Keychain
    /// without knowing the connector exists. The next sync is where its
    /// in-memory key has to go, or a reset the UI calls complete would leave
    /// it in the process.
    func testASyncAfterTheKeyIsGoneDropsTheConnectorsCopy() async throws {
        let connector = MockConnector()
        let sut = await makeService(connector: connector)
        _ = try await sut.syncRecentWorkouts()
        let beforeReset = await connector.didDisconnect
        XCTAssertFalse(beforeReset)

        try await keychain.delete(.hevyAPIKey)
        do {
            _ = try await sut.syncRecentWorkouts()
            XCTFail("Expected .missingAPIKey to be thrown")
        } catch {
            XCTAssertEqual(error as? WorkoutSyncError, .missingAPIKey)
        }

        let didDisconnect = await connector.didDisconnect
        XCTAssertTrue(didDisconnect)
    }

    // MARK: - Fan-out over the registry (#143)

    private func stravaRun(id: Int, daysAgo days: Int) -> Activity {
        Activity(id: "strava:\(id)", title: "Run", startTime: daysAgo(days), source: .strava)
    }

    func testSyncsEveryConnectedSourceAndCachesEachWindow() async throws {
        let hevy = MockConnector()
        await hevy.setFetchActivitiesResult(.success([ActivityFactory.activity(id: "hevy-1", start: daysAgo(1))]))
        let strava = MockConnector()
        await strava.setFetchActivitiesResult(.success([stravaRun(id: 1, daysAgo: 2)]))
        await connectStrava(strava)
        sut = await makeService(connector: hevy)

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.workoutCount, 2)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(result.isPartial)
        XCTAssertEqual(result.sources, [.hevy, .strava])
        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(Set(ids), ["hevy-1", "strava:1"])
        let stravaCredentials = await strava.lastConnectedCredentials
        XCTAssertEqual(stravaCredentials, Self.stravaPair, "the stored pair is what Strava is connected with")
        let stored = await timestamps.lastSync()
        XCTAssertEqual(stored, Self.now)
    }

    private func polarRun(id: Int, daysAgo days: Int) -> Activity {
        Activity(id: "polar:\(id)", title: "Run", startTime: daysAgo(days), source: .polar)
    }

    /// AC (#159): the sync fans out to Polar the same generic way it does to
    /// Strava — no Polar-specific branch in the fan-out itself.
    func testSyncsPolarAlongsideHevyAndStrava() async throws {
        let hevy = MockConnector()
        await hevy.setFetchActivitiesResult(.success([ActivityFactory.activity(id: "hevy-1", start: daysAgo(1))]))
        let strava = MockConnector()
        await strava.setFetchActivitiesResult(.success([stravaRun(id: 1, daysAgo: 2)]))
        await connectStrava(strava)
        let polar = MockConnector()
        await polar.setFetchActivitiesResult(.success([polarRun(id: 1, daysAgo: 3)]))
        await connectPolar(polar)
        sut = await makeService(connector: hevy)

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.workoutCount, 3)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.sources, [.hevy, .strava, .polar])
        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(Set(ids), ["hevy-1", "strava:1", "polar:1"])
        let polarCredentials = await polar.lastConnectedCredentials
        XCTAssertEqual(polarCredentials, Self.polarPair, "the stored pair is what Polar is connected with")
    }

    /// Polar is optional: registered but without a stored pair, it is simply
    /// not part of the sync.
    func testPolarWithoutStoredCredentialsIsSkipped() async throws {
        let polar = MockConnector()
        await registry.register(polar, for: .polar)
        sut = await makeService(connector: MockConnector())

        let result = try await sut.syncRecentWorkouts()

        XCTAssertTrue(result.failures.isEmpty)
        let fetches = await polar.fetchActivitiesCallCount
        XCTAssertEqual(fetches, 0)
    }

    /// A Polar fetch that refreshed its access token leaves the new pair in the
    /// shared store.
    func testARefreshedPolarPairIsPersistedBackToTheStore() async throws {
        let credentials = PolarClientCredentials(clientID: "c", clientSecret: "s")
        let oauth = StubPolarOAuthorizer(refreshResult: .success(
            .oauth(accessToken: "fresh-access", refreshToken: "fresh-refresh", expiresAt: Self.now.addingTimeInterval(43_199))
        ))
        let expiredPair = ConnectorCredentials.oauth(
            accessToken: "expired-access",
            refreshToken: "refresh-1",
            expiresAt: Self.now.addingTimeInterval(-1)
        )
        polarStore = StubPolarCredentialStore(clientCredentials: credentials, credentials: expiredPair)
        let polar = PolarConnector(
            accessLink: PolarAccessLinkClient(session: StubURLProtocol.makeSession()),
            oauth: oauth,
            credentialStore: polarStore,
            memberID: "member-1",
            now: { Self.now }
        )
        await registry.register(polar, for: .polar)
        StubURLProtocol.handler = { request in
            PolarTestSupport.http(200, for: request, body: "[]")
        }
        sut = await makeService(connector: MockConnector())

        _ = try await sut.syncRecentWorkouts()

        let stored = try await polarStore.credentials()
        XCTAssertEqual(
            stored,
            .oauth(accessToken: "fresh-access", refreshToken: "fresh-refresh", expiresAt: Self.now.addingTimeInterval(43_199))
        )
    }

    /// Strava is optional: registered but without a stored pair, it is simply
    /// not part of the sync.
    func testStravaWithoutStoredCredentialsIsSkipped() async throws {
        let strava = MockConnector()
        await registry.register(strava, for: .strava)
        sut = await makeService(connector: MockConnector())

        let result = try await sut.syncRecentWorkouts()

        XCTAssertTrue(result.failures.isEmpty)
        let fetches = await strava.fetchActivitiesCallCount
        XCTAssertEqual(fetches, 0)
    }

    /// The point of the fan-out: one source failing does not throw the
    /// other's fresh data away.
    func testStravaFailureLeavesHevyDataAndReportsIt() async throws {
        let hevy = MockConnector()
        await hevy.setFetchActivitiesResult(.success([ActivityFactory.activity(id: "hevy-1", start: daysAgo(1))]))
        let strava = MockConnector()
        await strava.setFetchActivitiesResult(.failure(.rateLimited(retryAfter: nil)))
        await connectStrava(strava)
        sut = await makeService(connector: hevy)

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.failures, [.strava: .rateLimited(retryAfter: nil)])
        XCTAssertTrue(result.isPartial)
        XCTAssertEqual(result.workoutCount, 1)
        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["hevy-1"])
        let stored = await timestamps.lastSync()
        XCTAssertEqual(stored, Self.now, "a partial sync still moves the timestamp")
    }

    func testHevyFailureLeavesStravaDataAndKeepsThePreviousHevyWindow() async throws {
        try await workouts.replaceCachedWorkouts(from: .hevy, with: [ActivityFactory.activity(id: "hevy-old", start: daysAgo(5))])
        let hevy = MockConnector()
        await hevy.setFetchActivitiesResult(.failure(.networkUnavailable))
        let strava = MockConnector()
        await strava.setFetchActivitiesResult(.success([stravaRun(id: 1, daysAgo: 2)]))
        await connectStrava(strava)
        sut = await makeService(connector: hevy)

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.failures, [.hevy: .networkUnavailable])
        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(Set(ids), ["hevy-old", "strava:1"], "the failed source keeps its previous window")
    }

    /// Nothing landed, so nothing to report a success about: the first
    /// source's error is the one thrown, and the timestamp stays put.
    func testEverySourceFailingThrowsTheFirstSourcesError() async {
        let hevy = MockConnector()
        await hevy.setFetchActivitiesResult(.failure(.serviceUnavailable))
        let strava = MockConnector()
        await strava.setFetchActivitiesResult(.failure(.networkUnavailable))
        await connectStrava(strava)
        sut = await makeService(connector: hevy)

        await assertSyncThrows(.serviceUnavailable)

        let stored = await timestamps.lastSync()
        XCTAssertNil(stored)
    }

    /// US-5 AC2 groundwork: a rejected Strava pair is the renewal case. It is
    /// reported, and nothing — not the pair, not the cache — is wiped, because
    /// only the user can renew it and the dashboard has to be able to say so.
    func testStravaUnauthorizedIsReportedWithoutWipingAnything() async throws {
        try await workouts.replaceCachedWorkouts(from: .strava, with: [stravaRun(id: 9, daysAgo: 9)])
        let hevy = MockConnector()
        await hevy.setFetchActivitiesResult(.success([ActivityFactory.activity(id: "hevy-1", start: daysAgo(1))]))
        let strava = MockConnector()
        await strava.setFetchActivitiesResult(.failure(.unauthorized))
        await connectStrava(strava)
        sut = await makeService(connector: hevy)

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.failures, [.strava: .unauthorized])
        let hevyKey = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(hevyKey, "hv_live_abc")
        let cleared = await stravaStore.clearCount
        XCTAssertEqual(cleared, 0)
        let stravaDisconnected = await strava.didDisconnect
        XCTAssertFalse(stravaDisconnected)
        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(Set(ids), ["hevy-1", "strava:9"], "the cached Strava window survives")
    }

    /// A rejected Hevy key ends the session whatever Strava did: the hard
    /// logout runs and the caller gets the throw it routes on (US-1 AC3).
    func testHevyUnauthorizedEndsTheSessionEvenWhenStravaSucceeds() async throws {
        let hevy = MockConnector()
        await hevy.setFetchActivitiesResult(.failure(.unauthorized))
        let strava = MockConnector()
        await strava.setFetchActivitiesResult(.success([stravaRun(id: 1, daysAgo: 2)]))
        await connectStrava(strava)
        sut = await makeService(connector: hevy)

        await assertSyncThrows(.unauthorized)

        let hevyKey = try await keychain.read(.hevyAPIKey)
        XCTAssertNil(hevyKey, "the hard logout must have run")
        let hevyDisconnected = await hevy.didDisconnect
        XCTAssertTrue(hevyDisconnected)
        let cleared = await stravaStore.clearCount
        XCTAssertEqual(cleared, 0, "Strava's pair is not Hevy's business")
    }

    /// A Keychain that refuses the Strava read is a failure the result
    /// carries — unlike a missing pair, which just means "not connected" —
    /// but only for a connection this process knows about: the read cannot
    /// tell whether a pair is in there, and a banner for a source the user
    /// never connected would be wrong. Either way the source counts as
    /// attempted, so `sources` lists it (the strip's contract).
    func testUnreadableStravaCredentialsAreReportedAsKeychainUnavailableForAKnownConnection() async throws {
        let strava = MockConnector()
        await connectStrava(strava)
        try await registry.connect(.strava, credentials: Self.stravaPair)
        await stravaStore.setFailReads(true)
        sut = await makeService(connector: MockConnector())

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.failures, [.strava: .keychainUnavailable])
        XCTAssertEqual(result.sources, [.hevy, .strava])
        let fetches = await strava.fetchActivitiesCallCount
        XCTAssertEqual(fetches, 0)
    }

    func testUnreadableStravaCredentialsAreNotReportedWithoutAKnownConnection() async throws {
        let strava = MockConnector()
        await connectStrava(strava)
        await stravaStore.setFailReads(true)
        sut = await makeService(connector: MockConnector())

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.failures, [:])
        XCTAssertEqual(result.sources, [.hevy])
        let fetches = await strava.fetchActivitiesCallCount
        XCTAssertEqual(fetches, 0)
    }

    /// A stored pair that is gone — disconnected by the user, or wiped by
    /// "delete all data" — takes the connector's in-memory copy with it on
    /// the next sync, as the Hevy key does (#83).
    func testASyncWithoutAStoredStravaPairDropsTheConnectorsCopy() async throws {
        let strava = MockConnector()
        await connectStrava(strava)
        try await registry.connect(.strava, credentials: Self.stravaPair)
        stravaStore = StubStravaCredentialStore()
        sut = await makeService(connector: MockConnector())

        _ = try await sut.syncRecentWorkouts()

        let didDisconnect = await strava.didDisconnect
        XCTAssertTrue(didDisconnect)
        let state = await registry.state(of: .strava, now: Self.now)
        XCTAssertEqual(state, .disconnected)
    }

    /// The connector tolerates a refresh whose persist failed (locked
    /// Keychain) and keeps the rotated pair in memory. The sync must not put
    /// the stale stored pair back — neither after the fetch nor at the start
    /// of the next one — or every later refresh would send a refresh token
    /// Strava has already rotated away.
    func testARefreshedPairThatCouldNotBePersistedIsNotOverwrittenByTheStoredOne() async throws {
        let oauth = StubStravaOAuthorizer()
        stravaStore = StubStravaCredentialStore(
            clientCredentials: StravaClientCredentials(clientID: "123456", clientSecret: "s3cr3t"),
            credentials: .oauth(accessToken: "access-old", refreshToken: "refresh-old", expiresAt: Self.now.addingTimeInterval(60))
        )
        await stravaStore.setFailWrites(true)
        await oauth.setRefreshResult(.success(
            .oauth(accessToken: "access-2", refreshToken: "refresh-2", expiresAt: Self.now.addingTimeInterval(6 * 3600))
        ))
        await registry.register(
            StravaConnector(session: StubURLProtocol.makeSession(), oauth: oauth, credentialStore: stravaStore, now: { Self.now }),
            for: .strava
        )
        StubURLProtocol.handler = { request in
            Self.captured.append(request)
            return (Self.http(status: 200, for: request, headers: nil), Data("[]".utf8))
        }
        let hevy = MockConnector()
        sut = await makeService(connector: hevy)

        let first = try await sut.syncRecentWorkouts()
        // Strava has rotated the pair away: the old refresh token is dead.
        await oauth.setRefreshResult(.failure(StravaOAuthError.invalidGrant))
        let second = try await sut.syncRecentWorkouts()

        XCTAssertEqual(first.failures, [:])
        XCTAssertEqual(second.failures, [:], "the rotated pair in memory must keep serving")
        let refreshes = await oauth.refreshCalls.map(\.refreshToken)
        XCTAssertEqual(refreshes, ["refresh-old"], "refreshed once, with the pair that was current then")
        XCTAssertEqual(Self.captured.compactMap { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer access-2", "Bearer access-2"])
    }

    // MARK: - Driven from the dashboard

    /// The whole chain the dashboard runs at launch and on pull-to-refresh —
    /// view model, sync service, registry, connectors — must carry a sync to
    /// completion. On a device every request of every sync was found cancelled
    /// a millisecond after starting; this pins down whether the service cancels
    /// itself or something above the view model does.
    @MainActor
    func testTheDashboardReloadRunsTheSyncToCompletion() async throws {
        let hevy = MockConnector()
        await hevy.setFetchActivitiesResult(.success([ActivityFactory.activity(id: "hevy-1", start: daysAgo(1))]))
        let strava = MockConnector()
        await strava.setFetchActivitiesResult(.success([stravaRun(id: 1, daysAgo: 2)]))
        await connectStrava(strava)
        let service = await makeService(connector: hevy)
        let viewModel = WorkoutListViewModel(cache: workouts, syncer: service, timestamps: timestamps, now: { Self.now })

        await viewModel.reload()

        XCTAssertEqual(viewModel.syncStatus, .idle)
        XCTAssertEqual(viewModel.lastSync, Self.now)
        let hevyFetches = await hevy.fetchActivitiesCallCount
        let stravaFetches = await strava.fetchActivitiesCallCount
        XCTAssertEqual(hevyFetches, 1)
        XCTAssertEqual(stravaFetches, 1)
        guard case .loaded(let summaries, _) = viewModel.state else {
            return XCTFail("expected .loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(Set(summaries.map(\.id)), ["hevy-1", "strava:1"])
    }

    // MARK: - Reset during a running sync (#150)

    /// A sync outlives the pull that started it (#150), so it can still be
    /// fetching when the user confirms "delete Hevy key" or "delete all data"
    /// (#83). Both remove the key before they empty the cache; the sync must
    /// notice and drop the window it fetched — writing it would restore what
    /// the user just deleted (US-1 AC3). It ends as a cancellation, not as
    /// `.missingAPIKey`: the dashboard must not route to onboarding a second
    /// time over a key the user removed themselves.
    func testAResetDuringTheFetchVoidsTheSyncInsteadOfRestoringTheCache() async throws {
        let connector = MockConnector()
        await connector.setFetchActivitiesResult(.success([ActivityFactory.activity(id: "a-1", start: daysAgo(1))]))
        sut = await makeService(connector: connector)
        _ = try await sut.syncRecentWorkouts()
        let cachedBefore = try await workouts.workoutCount()
        XCTAssertEqual(cachedBefore, 1)

        let reset = SessionResetService(
            keychain: keychain,
            workouts: workouts,
            results: AnalysisResultStore(modelContainer: workouts.modelContainer),
            timestamps: timestamps
        )
        await connector.setDuringFetch { await reset.hardLogout() }
        do {
            _ = try await sut.syncRecentWorkouts()
            XCTFail("Expected the voided sync to throw")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }

        let cachedAfter = try await workouts.workoutCount()
        XCTAssertEqual(cachedAfter, 0, "The reset must win over the sync running through it")
        let lastSync = await timestamps.lastSync()
        XCTAssertNil(lastSync)
        let didDisconnect = await connector.didDisconnect
        XCTAssertTrue(didDisconnect, "The connector's in-memory key goes with the stored one")
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
        _ expected: WorkoutSyncError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await sut.syncRecentWorkouts()
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as WorkoutSyncError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
