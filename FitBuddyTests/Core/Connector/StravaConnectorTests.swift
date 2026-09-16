import XCTest
@testable import FitBuddy

/// Unit tests for `StravaConnector` against a stubbed `URLProtocol`, a
/// `StubStravaOAuthorizer` and a `StubStravaCredentialStore` (#142).
///
/// Same split as `HevyConnectorTests`: the connector is tested on its own
/// contract — `FitnessConnector` in, `Activity`/`ConnectorError` out — plus
/// the one thing Hevy does not have, the token it has to keep alive.
final class StravaConnectorTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_754_400_000) // 2025-08-05 14:40 UTC

    private static let client = StravaClientCredentials(clientID: "123456", clientSecret: "s3cr3t")

    private var oauth: StubStravaOAuthorizer!
    private var store: StubStravaCredentialStore!
    private var sut: StravaConnector!

    nonisolated(unsafe) private static var captured: [URLRequest] = []
    nonisolated(unsafe) private static var pendingPages: [Data] = []

    override func setUp() async throws {
        try await super.setUp()
        Self.captured = []
        Self.pendingPages = []
        oauth = StubStravaOAuthorizer()
        store = StubStravaCredentialStore(clientCredentials: Self.client)
        sut = makeConnector()
        try await sut.connect(credentials: Self.freshPair)
    }

    override func tearDown() async throws {
        StubURLProtocol.handler = nil
        Self.captured = []
        Self.pendingPages = []
        sut = nil
        store = nil
        oauth = nil
        try await super.tearDown()
    }

    /// A pair with hours left on it.
    private static var freshPair: ConnectorCredentials {
        .oauth(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: now.addingTimeInterval(4 * 3600))
    }

    /// A pair inside the refresh leeway.
    private static var expiringPair: ConnectorCredentials {
        .oauth(accessToken: "access-old", refreshToken: "refresh-old", expiresAt: now.addingTimeInterval(60))
    }

    private static var renewedPair: ConnectorCredentials {
        .oauth(accessToken: "access-2", refreshToken: "refresh-2", expiresAt: now.addingTimeInterval(6 * 3600))
    }

    private func makeConnector() -> StravaConnector {
        StravaConnector(
            session: StubURLProtocol.makeSession(),
            oauth: oauth,
            credentialStore: store,
            now: { Self.now }
        )
    }

    // MARK: - Credentials

    func testItIsAFitnessConnector() {
        let connector: any FitnessConnector = makeConnector()
        XCTAssertTrue(connector is StravaConnector)
    }

    /// An API key means the caller wired up the wrong connector — Strava has
    /// no such scheme.
    func testConnectRejectsCredentialsThatAreNotAnOAuthPair() async {
        let fresh = makeConnector()

        do {
            try await fresh.connect(credentials: .apiKey("hv_live_abc"))
            XCTFail("Expected .unauthorized to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .unauthorized)
        }
    }

    func testConnectRejectsAnEmptyAccessToken() async {
        let fresh = makeConnector()

        do {
            try await fresh.connect(credentials: .oauth(accessToken: "", refreshToken: "r", expiresAt: Self.now))
            XCTFail("Expected .unauthorized to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .unauthorized)
        }
    }

    func testFetchWithoutCredentialsIsUnauthorizedAndSendsNoRequest() async {
        let fresh = makeConnector()
        StubURLProtocol.handler = { Self.response(status: 200, for: $0) }

        await assertFetchThrows(.unauthorized, on: fresh)
        XCTAssertTrue(Self.captured.isEmpty, "No request may be sent without a token")
    }

    func testDisconnectDropsTheTokens() async {
        await sut.disconnect()
        StubURLProtocol.handler = { Self.response(status: 200, for: $0) }

        await assertFetchThrows(.unauthorized)
        XCTAssertTrue(Self.captured.isEmpty)
    }

    // MARK: - Requests

    func testTheTokenTravelsAsABearerHeaderWithTheWindowAsAfter() async throws {
        stub(pages: [StravaPayloadFactory.page([])])
        let since = Self.daysAgo(90)

        _ = try await sut.fetchActivities(since: since)

        let request = try XCTUnwrap(Self.captured.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(request.url?.host, "www.strava.com")
        XCTAssertEqual(request.url?.path, "/api/v3/athlete/activities")
        XCTAssertEqual(Self.queryValue("after", in: request), String(Int(since.timeIntervalSince1970)))
        XCTAssertEqual(Self.queryValue("page", in: request), "1")
        XCTAssertEqual(Self.queryValue("per_page", in: request), "100")
    }

    // MARK: - Normalization (ADR-6, ADR-10)

    /// The shape the whole "Strava field analysis" came down to: one exercise
    /// named after the sport, one set carrying distance and moving time.
    func testARunComesBackAsOneExerciseWithOneCardioSet() async throws {
        let start = Self.daysAgo(1)
        stub(pages: [StravaPayloadFactory.page([
            StravaPayloadFactory.activity(id: 987, start: start, distance: 5000, movingTime: 1800, elapsedTime: 1900),
        ])])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        let activity = try XCTUnwrap(activities.first)
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activity.id, "strava:987")
        XCTAssertEqual(activity.title, "Morning Run")
        XCTAssertEqual(activity.source, .strava)
        XCTAssertEqual(activity.startTime, start)
        XCTAssertEqual(activity.endTime, start.addingTimeInterval(1900))
        XCTAssertNil(activity.updatedAt)

        let exercise = try XCTUnwrap(activity.exercises.first)
        XCTAssertEqual(activity.exercises.count, 1)
        XCTAssertEqual(exercise.index, 0)
        XCTAssertEqual(exercise.title, "Run")

        let set = try XCTUnwrap(exercise.sets.first)
        XCTAssertEqual(exercise.sets.count, 1)
        XCTAssertEqual(set.type, .normal)
        XCTAssertEqual(set.distanceMeters, 5000)
        XCTAssertEqual(set.durationSeconds, 1800)
        XCTAssertNil(set.weightKg)
        XCTAssertNil(set.reps)
    }

    func testZeroDistanceAndDurationDecodeAsNotLogged() async throws {
        stub(pages: [StravaPayloadFactory.page([
            StravaPayloadFactory.activity(id: 1, start: Self.daysAgo(1), name: "Yoga", sportType: "Yoga", distance: 0, movingTime: 0),
        ])])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))
        let set = try XCTUnwrap(activities.first?.exercises.first?.sets.first)

        XCTAssertNil(set.distanceMeters)
        XCTAssertNil(set.durationSeconds)
    }

    func testMissingNameFallsBackToTheSportAndMissingSportTypeToType() async throws {
        stub(pages: [StravaPayloadFactory.page([
            StravaPayloadFactory.activity(id: 1, start: Self.daysAgo(1), name: nil, sportType: nil, type: "Ride"),
        ])])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))
        let activity = try XCTUnwrap(activities.first)

        XCTAssertEqual(activity.title, "Ride")
        XCTAssertEqual(activity.exercises.first?.title, "Ride")
    }

    // MARK: - Pagination

    func testWalksPagesUntilAShortOneAndReturnsNewestFirst() async throws {
        // Strava's `after` filter lists oldest first; a full page of 100 is
        // followed by a short one, which is the last.
        let fullPage = (1...100).map { index in
            StravaPayloadFactory.activity(id: Int64(index), start: Self.daysAgo(90 - index / 2))
        }
        let shortPage = [StravaPayloadFactory.activity(id: 101, start: Self.daysAgo(1))]
        stub(pages: [StravaPayloadFactory.page(fullPage), StravaPayloadFactory.page(shortPage)])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertEqual(activities.count, 101)
        XCTAssertEqual(activities.first?.id, "strava:101", "newest first, whatever order Strava served")
        XCTAssertEqual(Self.captured.compactMap { Self.queryValue("page", in: $0) }, ["1", "2"])
    }

    func testAnEmptyFirstPageEndsTheWalk() async throws {
        stub(pages: [StravaPayloadFactory.page([])])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertTrue(activities.isEmpty)
        XCTAssertEqual(Self.captured.count, 1)
    }

    func testActivityRepeatedAcrossAPageBoundaryIsReturnedOnce() async throws {
        let fullPage = (1...100).map { index in
            StravaPayloadFactory.activity(id: Int64(index), start: Self.daysAgo(80))
        }
        // The last entry of page 1 shows up again at the top of page 2.
        let secondPage = [
            StravaPayloadFactory.activity(id: 100, start: Self.daysAgo(80)),
            StravaPayloadFactory.activity(id: 101, start: Self.daysAgo(1)),
        ]
        stub(pages: [StravaPayloadFactory.page(fullPage), StravaPayloadFactory.page(secondPage)])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertEqual(activities.count, 101)
        XCTAssertEqual(activities.filter { $0.id == "strava:100" }.count, 1)
    }

    func testKeepsOnlyActivitiesAtOrAfterTheRequestedCutOff() async throws {
        stub(pages: [StravaPayloadFactory.page([
            StravaPayloadFactory.activity(id: 1, start: Self.daysAgo(1)),
            StravaPayloadFactory.activity(id: 2, start: Self.daysAgo(95)),
        ])])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertEqual(activities.map(\.id), ["strava:1"])
    }

    // MARK: - Refresh (US-5 AC4)

    func testValidateWithAFreshPairPingsTheAthleteEndpointAndDoesNotRefresh() async throws {
        StubURLProtocol.handler = { Self.response(status: 200, for: $0) }

        let valid = try await sut.validate()

        XCTAssertTrue(valid)
        XCTAssertEqual(Self.captured.first?.url?.path, "/api/v3/athlete")
        let refreshes = await oauth.refreshCalls.count
        XCTAssertEqual(refreshes, 0)
    }

    func testValidateReturnsFalseWhenStravaRejectsTheToken() async throws {
        StubURLProtocol.handler = { Self.response(status: 401, for: $0) }

        let valid = try await sut.validate()

        XCTAssertFalse(valid)
    }

    /// An expiring pair is refreshed exactly once, the rotated pair is
    /// persisted, and the answer is yes — no ping needed.
    func testValidateRefreshesAnExpiringPairAndPersistsTheRotatedOne() async throws {
        try await sut.connect(credentials: Self.expiringPair)
        await oauth.setRefreshResult(.success(Self.renewedPair))
        StubURLProtocol.handler = { Self.response(status: 200, for: $0) }

        let valid = try await sut.validate()

        XCTAssertTrue(valid)
        let refreshes = await oauth.refreshCalls
        XCTAssertEqual(refreshes.count, 1)
        XCTAssertEqual(refreshes.first?.refreshToken, "refresh-old")
        XCTAssertEqual(refreshes.first?.client, Self.client)
        let saved = await store.savedTokenPairs
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.accessToken, "access-2")
        XCTAssertEqual(saved.first?.refreshToken, "refresh-2", "the rotated refresh token must be what gets stored")
        XCTAssertTrue(Self.captured.isEmpty, "a successful refresh is the answer; no ping follows")
    }

    /// The transparent part of AC4: a sync with an expiring token succeeds
    /// without the user doing anything, and the request carries the new token.
    func testFetchRefreshesAnExpiringPairAndUsesTheNewToken() async throws {
        try await sut.connect(credentials: Self.expiringPair)
        await oauth.setRefreshResult(.success(Self.renewedPair))
        stub(pages: [StravaPayloadFactory.page([StravaPayloadFactory.activity(id: 1, start: Self.daysAgo(1))])])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(Self.captured.first?.value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
        let refreshes = await oauth.refreshCalls.count
        XCTAssertEqual(refreshes, 1)
    }

    func testARefreshedPairIsNotRefreshedAgainOnTheNextCall() async throws {
        try await sut.connect(credentials: Self.expiringPair)
        await oauth.setRefreshResult(.success(Self.renewedPair))
        stub(pages: [StravaPayloadFactory.page([])])

        _ = try await sut.fetchActivities(since: Self.daysAgo(90))
        _ = try await sut.fetchActivities(since: Self.daysAgo(90))

        let refreshes = await oauth.refreshCalls.count
        XCTAssertEqual(refreshes, 1)
    }

    /// A revoked or already-rotated refresh token: only the user can renew
    /// the connection, so the fetch reports it as an auth failure and
    /// `validate` as a no.
    func testRejectedRefreshIsUnauthorizedOnFetchAndFalseOnValidate() async throws {
        try await sut.connect(credentials: Self.expiringPair)
        await oauth.setRefreshResult(.failure(StravaOAuthError.invalidGrant))
        StubURLProtocol.handler = { Self.response(status: 200, for: $0) }

        await assertFetchThrows(.unauthorized)

        XCTAssertTrue(Self.captured.isEmpty, "no request may be sent with a token Strava rejected")
        let saved = await store.savedTokenPairs.count
        XCTAssertEqual(saved, 0)
    }

    /// The rejected pair is dropped: Strava has rotated it away, and every
    /// later call in the process would otherwise re-send the dead refresh
    /// token — one round-trip each against the application's rate limit.
    func testARejectedRefreshDropsThePairSoLaterCallsSendNothing() async throws {
        try await sut.connect(credentials: Self.expiringPair)
        await oauth.setRefreshResult(.failure(StravaOAuthError.invalidGrant))
        StubURLProtocol.handler = { Self.response(status: 200, for: $0) }

        await assertFetchThrows(.unauthorized)
        await assertFetchThrows(.unauthorized)
        do {
            _ = try await sut.validate()
            XCTFail("Expected .unauthorized: there is no pair left to validate")
        } catch let error as ConnectorError {
            XCTAssertEqual(error, .unauthorized)
        }

        let refreshes = await oauth.refreshCalls.count
        XCTAssertEqual(refreshes, 1, "the dead refresh token is sent once, not on every call")
        XCTAssertTrue(Self.captured.isEmpty)
    }

    /// A refresh interrupted by task cancellation is neither a rejected pair
    /// nor a connectivity problem — it travels out as the cancellation it is,
    /// like a cancelled request in `get()`.
    func testACancelledRefreshPropagatesAsACancellation() async throws {
        try await sut.connect(credentials: Self.expiringPair)
        await oauth.setRefreshResult(.failure(StravaOAuthError.cancelled))

        do {
            _ = try await sut.fetchActivities(since: Self.daysAgo(90))
            XCTFail("Expected the cancellation to propagate")
        } catch {
            XCTAssertTrue(error.isCancellation, "Unexpected error: \(error)")
        }

        await oauth.setRefreshResult(.failure(CancellationError()))
        do {
            _ = try await sut.validate()
            XCTFail("Expected the cancellation to propagate")
        } catch {
            XCTAssertTrue(error.isCancellation, "Unexpected error: \(error)")
        }
    }

    func testRefreshWithoutClientCredentialsIsRejected() async throws {
        store = StubStravaCredentialStore(clientCredentials: nil)
        sut = makeConnector()
        try await sut.connect(credentials: Self.expiringPair)
        await oauth.setRefreshResult(.success(Self.renewedPair))

        await assertFetchThrows(.unauthorized)
        let refreshes = await oauth.refreshCalls.count
        XCTAssertEqual(refreshes, 0, "there is no refresh grant to send without client credentials")
    }

    /// Offline during a refresh is a network problem, not a revoked token —
    /// reporting it as `unauthorized` would make the user re-authorize a
    /// connection that works.
    func testRefreshTransportFailureIsNetworkUnavailable() async throws {
        try await sut.connect(credentials: Self.expiringPair)
        await oauth.setRefreshResult(.failure(StravaOAuthError.transport))

        await assertFetchThrows(.networkUnavailable)
    }

    func testRefreshServerErrorIsServiceUnavailable() async throws {
        try await sut.connect(credentials: Self.expiringPair)
        await oauth.setRefreshResult(.failure(StravaOAuthError.unexpectedStatus(503)))

        await assertFetchThrows(.serviceUnavailable)
    }

    // MARK: - Error mapping

    func testUnauthorizedIsReportedWithoutTheConnectorActingOnIt() async throws {
        StubURLProtocol.handler = { Self.response(status: 401, for: $0) }

        await assertFetchThrows(.unauthorized)

        // The pair stays in the connector: renewing the session is the
        // caller's decision, and a `validate()` right after must still be
        // able to ask.
        StubURLProtocol.handler = { Self.response(status: 200, for: $0) }
        let recovered = try await sut.validate()
        XCTAssertTrue(recovered)
    }

    func testRateLimitedCarriesNoRetryAfter() async {
        StubURLProtocol.handler = { Self.response(status: 429, for: $0, headers: ["X-RateLimit-Usage": "201,1200"]) }
        await assertFetchThrows(.rateLimited(retryAfter: nil))
    }

    func testServerErrorMapsToServiceUnavailable() async {
        StubURLProtocol.handler = { Self.response(status: 503, for: $0) }
        await assertFetchThrows(.serviceUnavailable)
    }

    func testForbiddenIsNotAnAuthFailure() async {
        StubURLProtocol.handler = { Self.response(status: 403, for: $0) }
        await assertFetchThrows(.invalidResponse)
    }

    func testTransportFailureMapsToNetworkUnavailable() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertFetchThrows(.networkUnavailable)
    }

    func testMalformedBodyMapsToInvalidResponse() async {
        StubURLProtocol.handler = { request in
            (Self.http(status: 200, for: request, headers: nil), Data("<html>".utf8))
        }
        await assertFetchThrows(.invalidResponse)
    }

    func testCancellationIsNotReportedAsANetworkFailure() async {
        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }

        do {
            _ = try await sut.fetchActivities(since: Self.daysAgo(90))
            XCTFail("Expected the cancellation to propagate")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

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
            url: request.url ?? URL(staticString: "https://www.strava.com/api/v3/athlete/activities"),
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        ) ?? HTTPURLResponse()
    }

    private static func queryValue(_ name: String, in request: URLRequest) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first { $0.name == name }?.value
    }

    private static func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 24 * 3600)
    }

    private func assertFetchThrows(
        _ expected: ConnectorError,
        on connector: StravaConnector? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await (connector ?? sut).fetchActivities(since: Self.daysAgo(90))
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as ConnectorError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
