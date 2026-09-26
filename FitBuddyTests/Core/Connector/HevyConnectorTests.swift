import XCTest
@testable import FitBuddy

/// Unit tests for `HevyConnector` against a stubbed `URLProtocol` (#34).
///
/// The connector is tested on its own contract — `FitnessConnector` in,
/// `Activity`/`ConnectorError` out. What happens with the result afterwards
/// (Keychain, cache, timestamp, hard logout) belongs to
/// `WorkoutSyncServiceTests`; the point of the split is that the connector
/// cannot reach any of it.
final class HevyConnectorTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_754_400_000) // 2025-08-05 14:40 UTC

    private var sut: HevyConnector!

    /// Requests the stub answered, in order.
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    /// Workout page bodies the stub still has to hand out, in order.
    nonisolated(unsafe) private static var pendingPages: [Data] = []
    /// Routine page bodies the stub still has to hand out, in order.
    nonisolated(unsafe) private static var pendingRoutinePages: [Data] = []

    override func setUp() async throws {
        try await super.setUp()
        Self.captured = []
        Self.pendingPages = []
        Self.pendingRoutinePages = []
        sut = HevyConnector(session: StubURLProtocol.makeSession())
        try await sut.connect(credentials: .apiKey("hv_live_abc"))
    }

    override func tearDown() async throws {
        StubURLProtocol.handler = nil
        Self.captured = []
        Self.pendingPages = []
        Self.pendingRoutinePages = []
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Credentials

    func testFetchWithoutCredentialsIsUnauthorizedAndSendsNoRequest() async {
        let fresh = HevyConnector(session: StubURLProtocol.makeSession())
        StubURLProtocol.handler = { Self.response(status: 200, for: $0) }

        await assertFetchThrows(.unauthorized, on: fresh)
        XCTAssertTrue(Self.captured.isEmpty, "No request may be sent without a key")
    }

    /// An OAuth pair means the caller wired up the wrong connector — Hevy has
    /// no such flow, and sending a keyless request would fail less clearly.
    func testConnectRejectsCredentialsThatAreNotAnAPIKey() async {
        let fresh = HevyConnector(session: StubURLProtocol.makeSession())

        do {
            try await fresh.connect(
                credentials: .oauth(accessToken: "a", refreshToken: "r", expiresAt: Self.now)
            )
            XCTFail("Expected .unauthorized to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .unauthorized)
        }
    }

    /// An empty key is no key: sending it would spend a request to be told
    /// what the connector already knows.
    func testConnectRejectsAnEmptyAPIKey() async {
        let fresh = HevyConnector(session: StubURLProtocol.makeSession())

        do {
            try await fresh.connect(credentials: .apiKey(""))
            XCTFail("Expected .unauthorized to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .unauthorized)
        }
    }

    func testDisconnectDropsTheKey() async {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [])])

        await sut.disconnect()

        await assertFetchThrows(.unauthorized)
    }

    func testTheKeyTravelsAsTheAPIKeyHeader() async throws {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [])])

        _ = try await sut.fetchActivities(since: Self.daysAgo(90))

        let request = try XCTUnwrap(Self.captured.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "hv_live_abc")
        XCTAssertEqual(request.url?.path, "/v1/workouts")
        XCTAssertEqual(Self.queryValue("pageSize", in: request), "10")
    }

    // MARK: - validate()

    func testValidateProbesWithASinglePageAndReturnsTrue() async throws {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [])])

        let isValid = try await sut.validate()

        XCTAssertTrue(isValid)
        let request = try XCTUnwrap(Self.captured.first)
        XCTAssertEqual(Self.captured.count, 1, "Validation must not walk the history")
        XCTAssertEqual(Self.queryValue("pageSize", in: request), "1")
    }

    /// A rejected key is an answer, not a failure — the contract says `false`,
    /// and only a real problem throws.
    func testValidateReturnsFalseWhenHevyRejectsTheKey() async throws {
        StubURLProtocol.handler = { Self.response(status: 401, for: $0) }

        let isValid = try await sut.validate()

        XCTAssertFalse(isValid)
    }

    func testValidateThrowsWhenTheAnswerIsNotAYesOrNo() async {
        StubURLProtocol.handler = { Self.response(status: 503, for: $0) }

        do {
            _ = try await sut.validate()
            XCTFail("Expected .serviceUnavailable to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .serviceUnavailable)
        }
    }

    // MARK: - Normalization (ADR-6)

    func testWireWorkoutsComeBackAsNormalizedActivities() async throws {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
            HevyPayloadFactory.workout(id: "w-1", start: Self.daysAgo(1)),
        ])])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        let activity = try XCTUnwrap(activities.first)
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activity.id, "w-1")
        XCTAssertEqual(activity.title, "Morning Workout")
        // The session's free text survives normalization: it is rendered in the
        // detail view, and the round trip through `Activity` is where it would
        // silently go missing.
        XCTAssertEqual(activity.notes, "Felt strong")
        XCTAssertEqual(activity.updatedAt, activity.endTime)

        let exercise = try XCTUnwrap(activity.exercises.first)
        XCTAssertEqual(exercise.title, "Bench Press (Barbell)")
        XCTAssertEqual(exercise.notes, "Paid attention to form")
        XCTAssertEqual(exercise.templateID, "05293BCA")
        // The superset marker the detail card renders; `nil` here would be
        // indistinguishable from a mapping that dropped it.
        XCTAssertEqual(exercise.supersetID, 1)
        XCTAssertEqual(exercise.sets.map(\.type), [.warmup, .normal])
        XCTAssertEqual(exercise.sets.last?.reps, 8)
        XCTAssertEqual(exercise.sets.last?.rpe, 9.5)
    }

    // MARK: - Pagination

    func testWalksEveryPageUntilPageCountIsReached() async throws {
        stub(pages: (1...3).map { page in
            HevyPayloadFactory.page(page: page, pageCount: 3, workouts: [
                HevyPayloadFactory.workout(id: "w-\(page)", start: Self.daysAgo(page)),
            ])
        })

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertEqual(activities.map(\.id), ["w-1", "w-2", "w-3"])
        XCTAssertEqual(Self.captured.compactMap { Self.queryValue("page", in: $0) }, ["1", "2", "3"])
    }

    func testKeepsOnlyActivitiesAtOrAfterTheRequestedCutOff() async throws {
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
            HevyPayloadFactory.workout(id: "inside", start: Self.daysAgo(1)),
            HevyPayloadFactory.workout(id: "outside", start: Self.daysAgo(95)),
        ])])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertEqual(activities.map(\.id), ["inside"])
    }

    func testActivityRepeatedAcrossAPageBoundaryIsReturnedOnce() async throws {
        // Hevy paginates newest first over a live list: a workout logged while
        // the walk is between two pages comes back on the next page as well.
        stub(pages: [
            HevyPayloadFactory.page(page: 1, pageCount: 2, workouts: [
                HevyPayloadFactory.workout(id: "newest", start: Self.daysAgo(1)),
                HevyPayloadFactory.workout(id: "boundary", start: Self.daysAgo(2)),
            ]),
            HevyPayloadFactory.page(page: 2, pageCount: 2, workouts: [
                HevyPayloadFactory.workout(id: "boundary", start: Self.daysAgo(2)),
                HevyPayloadFactory.workout(id: "oldest", start: Self.daysAgo(3)),
            ]),
        ])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertEqual(activities.map(\.id), ["newest", "boundary", "oldest"])
    }

    // MARK: - Routine targets (#240)

    func testAWorkoutNamingARoutineGetsItsTargetsFromASecondEndpoint() async throws {
        let updatedAt = Self.daysAgo(30)
        stub(
            workoutPages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
                HevyPayloadFactory.workout(id: "w-1", start: Self.daysAgo(1), routineID: "r-1"),
            ])],
            routinePages: [HevyPayloadFactory.routinesPage(page: 1, pageCount: 1, routines: [
                HevyPayloadFactory.routine(id: "r-1", updatedAt: updatedAt),
            ])]
        )

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        let activity = try XCTUnwrap(activities.first)
        XCTAssertEqual(activity.routineID, "r-1")
        XCTAssertEqual(activity.routineUpdatedAt, updatedAt)
        XCTAssertEqual(activity.exercises.first?.sets.map(\.targetReps), [10, 12])
        XCTAssertEqual(Self.captured.map { $0.url?.path }, ["/v1/workouts", "/v1/routines"])
        let routinesRequest = try XCTUnwrap(Self.captured.last)
        XCTAssertEqual(routinesRequest.value(forHTTPHeaderField: "api-key"), "hv_live_abc")
        XCTAssertEqual(Self.queryValue("pageSize", in: routinesRequest), "10")
    }

    /// Logging freely is the common case, and it must not cost a request.
    func testWorkoutsWithoutARoutineSendNoRoutinesRequest() async throws {
        stub(workoutPages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
            HevyPayloadFactory.workout(id: "w-1", start: Self.daysAgo(1)),
        ])])

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertEqual(activities.first?.routineID, nil)
        XCTAssertEqual(activities.first?.exercises.first?.sets.map(\.targetReps), [nil, nil])
        XCTAssertEqual(Self.captured.map { $0.url?.path }, ["/v1/workouts"])
    }

    /// A routine the user deleted since is absent from the library. The
    /// session keeps its id, carries no targets, and the sync succeeds.
    func testARoutineMissingFromTheLibraryIsNotAFailure() async throws {
        stub(
            workoutPages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
                HevyPayloadFactory.workout(id: "w-1", start: Self.daysAgo(1), routineID: "r-gone"),
            ])],
            routinePages: [HevyPayloadFactory.routinesPage(page: 1, pageCount: 1, routines: [
                HevyPayloadFactory.routine(id: "r-other", updatedAt: Self.daysAgo(30)),
            ])]
        )

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertEqual(activities.first?.routineID, "r-gone")
        XCTAssertNil(activities.first?.routineUpdatedAt)
        XCTAssertEqual(activities.first?.exercises.first?.sets.map(\.targetReps), [nil, nil])
    }

    /// The library has no filter, so it is walked — but only until every
    /// routine the window names has been found.
    func testTheRoutineWalkStopsOnceEveryNamedRoutineIsFound() async throws {
        stub(
            workoutPages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
                HevyPayloadFactory.workout(id: "w-1", start: Self.daysAgo(1), routineID: "r-2"),
                HevyPayloadFactory.workout(id: "w-2", start: Self.daysAgo(2), routineID: "r-1"),
            ])],
            routinePages: [
                HevyPayloadFactory.routinesPage(page: 1, pageCount: 3, routines: [
                    HevyPayloadFactory.routine(id: "r-1", updatedAt: Self.daysAgo(30)),
                ]),
                HevyPayloadFactory.routinesPage(page: 2, pageCount: 3, routines: [
                    HevyPayloadFactory.routine(id: "r-2", updatedAt: Self.daysAgo(20)),
                ]),
                HevyPayloadFactory.routinesPage(page: 3, pageCount: 3, routines: [
                    HevyPayloadFactory.routine(id: "r-3", updatedAt: Self.daysAgo(10)),
                ]),
            ]
        )

        let activities = try await sut.fetchActivities(since: Self.daysAgo(90))

        XCTAssertEqual(activities.map(\.routineUpdatedAt), [Self.daysAgo(20), Self.daysAgo(30)])
        let routinePages = Self.captured
            .filter { $0.url?.path == "/v1/routines" }
            .compactMap { Self.queryValue("page", in: $0) }
        XCTAssertEqual(routinePages, ["1", "2"], "Page 3 holds nothing the window needs")
    }

    /// The routines share the key and the error mapping with the workouts:
    /// a rejected key on the second endpoint is the same answer as on the
    /// first.
    func testAFailureOnTheRoutinesEndpointPropagates() async {
        stub(
            workoutPages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [
                HevyPayloadFactory.workout(id: "w-1", start: Self.daysAgo(1), routineID: "r-1"),
            ])],
            routinePages: [],
            routineStatus: 503
        )

        await assertFetchThrows(.serviceUnavailable)
    }

    // MARK: - Error mapping

    func testUnauthorizedIsReportedWithoutTheConnectorActingOnIt() async throws {
        StubURLProtocol.handler = { Self.response(status: 401, for: $0) }

        await assertFetchThrows(.unauthorized)

        // The key stays in the connector: wiping the session is the caller's
        // decision (US-1 AC3), and a `validate()` right after must still be
        // able to ask.
        stub(pages: [HevyPayloadFactory.page(page: 1, pageCount: 1, workouts: [])])
        let recovered = try await sut.validate()
        XCTAssertTrue(recovered)
    }

    func testRateLimitedCarriesRetryAfter() async {
        StubURLProtocol.handler = { Self.response(status: 429, for: $0, headers: ["Retry-After": "30"]) }
        await assertFetchThrows(.rateLimited(retryAfter: 30))
    }

    func testServerErrorMapsToServiceUnavailable() async {
        StubURLProtocol.handler = { Self.response(status: 503, for: $0) }
        await assertFetchThrows(.serviceUnavailable)
    }

    /// 403 hits valid keys too (WAF, geo). `ConnectorError` has no case for an
    /// odd status, and reporting it as `.unauthorized` would make the caller
    /// wipe a working key.
    func testForbiddenIsNotAnAuthFailure() async {
        StubURLProtocol.handler = { Self.response(status: 403, for: $0) }
        await assertFetchThrows(.invalidResponse)
    }

    func testTransportFailureMapsToNetworkUnavailable() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertFetchThrows(.networkUnavailable)
    }

    /// A failed certificate check (pinning, #153) is not "no internet": the
    /// user has to leave the network, not look for reception.
    func testCertificateFailureMapsToUntrustedConnection() async {
        StubURLProtocol.handler = { _ in throw URLError(.serverCertificateUntrusted) }
        await assertFetchThrows(.untrustedConnection)
    }

    func testMalformedBodyMapsToInvalidResponse() async {
        StubURLProtocol.handler = { request in
            (Self.http(status: 200, for: request, headers: nil), Data("not json".utf8))
        }
        await assertFetchThrows(.invalidResponse)
    }

    func testCancellationIsNotReportedAsANetworkFailure() async {
        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }

        do {
            _ = try await sut.fetchActivities(since: Self.daysAgo(90))
            XCTFail("Expected the cancellation to propagate")
        } catch let error as URLError {
            // Navigating away mid-sync must not surface as "no internet".
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    /// Answers `/v1/workouts` with `pages` in order; the last page repeats if
    /// the connector asks for more, so an over-eager walk shows up as an extra
    /// captured request rather than as a stub failure. `/v1/routines` answers
    /// with an empty library.
    private func stub(pages: [Data]) {
        stub(workoutPages: pages)
    }

    /// Answers each endpoint with its own pages, in order, the last one
    /// repeating (see `stub(pages:)`). `routineStatus` other than 200 answers
    /// the routines endpoint with that status and an empty body.
    private func stub(workoutPages: [Data], routinePages: [Data] = [], routineStatus: Int = 200) {
        Self.captured = []
        Self.pendingPages = workoutPages
        Self.pendingRoutinePages = routinePages
        StubURLProtocol.handler = { request in
            Self.captured.append(request)
            if request.url?.path == "/v1/routines" {
                guard routineStatus == 200 else {
                    return (Self.http(status: routineStatus, for: request, headers: nil), Data())
                }
                let body = Self.pendingRoutinePages.count > 1
                    ? Self.pendingRoutinePages.removeFirst()
                    : (Self.pendingRoutinePages.first
                        ?? HevyPayloadFactory.routinesPage(page: 1, pageCount: 1, routines: []))
                return (Self.http(status: 200, for: request, headers: nil), body)
            }
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
        // Test fixture: the URL comes from the request the stub just answered.
        HTTPURLResponse(
            url: request.url ?? URL(staticString: "https://api.hevyapp.com/v1/workouts"),
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

    /// `days` before the fixed clock.
    private static func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 24 * 3600)
    }

    private func assertFetchThrows(
        _ expected: ConnectorError,
        on connector: HevyConnector? = nil,
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
