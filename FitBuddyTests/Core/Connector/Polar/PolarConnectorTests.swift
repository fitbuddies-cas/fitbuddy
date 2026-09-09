import XCTest
@testable import FitBuddy

final class PolarConnectorTests: XCTestCase {
    private let configuration = PolarClientConfiguration(
        clientID: "fitbuddy-client",
        redirectURI: "fitbuddy://polar-oauth"
    )
    private let epoch = Date(timeIntervalSince1970: 1_000_000)
    private var sut: PolarConnector!

    override func setUp() {
        super.setUp()
        sut = PolarConnector(
            configuration: configuration,
            memberID: "member-42",
            session: StubURLProtocol.makeSession(),
            now: { [epoch] in epoch }
        )
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func liveCredentials(expiresIn: TimeInterval = 3600) -> ConnectorCredentials {
        .oauth(accessToken: "at", refreshToken: "rt", expiresAt: epoch.addingTimeInterval(expiresIn))
    }

    private static func exercisesBody() -> String {
        #"""
        [
          {
            "id": "old", "start-time": "2020-01-01T08:00:00", "start-time-utc-offset": 0,
            "duration": "PT30M"
          },
          {
            "id": "new", "start-time": "2020-06-01T08:00:00", "start-time-utc-offset": 0,
            "duration": "PT45M", "heart-rate": { "average": 150, "maximum": 175 }, "sport": "RUNNING"
          }
        ]
        """#
    }

    /// Routes the stub by path: token / users / exercises.
    private func route(
        exercisesStatus: Int = 200,
        exercisesBody: String = PolarConnectorTests.exercisesBody(),
        usersStatus: Int = 201,
        tokenBody: String = #"{"access_token":"fresh-at","refresh_token":"fresh-rt","expires_in":43199}"#
    ) {
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/oauth/token":
                return PolarTestSupport.http(200, for: request, body: tokenBody)
            case "/v3/users":
                return PolarTestSupport.http(usersStatus, for: request)
            case "/v3/exercises":
                return PolarTestSupport.http(exercisesStatus, for: request, body: exercisesBody)
            default:
                return PolarTestSupport.http(404, for: request)
            }
        }
    }

    // MARK: - connect

    func testConnectRejectsAnAPIKeyCredentialSincePolarHasNoSuchThing() async {
        await assertThrowsConnectorError(.unauthorized) {
            try await self.sut.connect(credentials: .apiKey("nope"))
        }
    }

    // MARK: - fetchActivities

    func testReturnsOnlyActivitiesInsideTheWindowNewestFirst() async throws {
        route()
        try await sut.connect(credentials: liveCredentials())

        let activities = try await sut.fetchActivities(
            since: ISO8601DateFormatter().date(from: "2020-03-01T00:00:00Z")!
        )

        XCTAssertEqual(activities.map(\.id), ["polar-new"])
        XCTAssertEqual(activities.first?.metrics?.averageHeartRate, 150)
        XCTAssertEqual(activities.first?.title, "Running")
    }

    func testRegistersTheUserOnlyOnceAcrossSeveralSyncs() async throws {
        nonisolated(unsafe) var userCalls = 0
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v3/users":
                userCalls += 1
                return PolarTestSupport.http(201, for: request)
            case "/v3/exercises":
                return PolarTestSupport.http(204, for: request)
            default:
                return PolarTestSupport.http(404, for: request)
            }
        }
        try await sut.connect(credentials: liveCredentials())

        _ = try await sut.fetchActivities(since: .distantPast)
        _ = try await sut.fetchActivities(since: .distantPast)

        XCTAssertEqual(userCalls, 1)
    }

    func testAlreadyRegisteredUser409IsTreatedAsSuccess() async throws {
        route(usersStatus: 409)
        try await sut.connect(credentials: liveCredentials())

        let activities = try await sut.fetchActivities(since: .distantPast)

        XCTAssertEqual(activities.count, 2)
    }

    func testExpiredAccessTokenIsRefreshedBeforeTheDataCall() async throws {
        route()
        try await sut.connect(credentials: liveCredentials(expiresIn: 10)) // inside the 60s leeway

        _ = try await sut.fetchActivities(since: .distantPast)

        let refreshed = await sut.currentCredentials()
        XCTAssertEqual(
            refreshed,
            .oauth(
                accessToken: "fresh-at",
                refreshToken: "fresh-rt",
                expiresAt: epoch.addingTimeInterval(43_199)
            )
        )
    }

    func testRateLimitedExerciseCallSurfacesRetryAfter() async throws {
        StubURLProtocol.handler = { request in
            if request.url?.path == "/v3/exercises" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "120"]
                )!
                return (response, Data())
            }
            return PolarTestSupport.http(201, for: request)
        }
        try await sut.connect(credentials: liveCredentials())

        await assertThrowsConnectorError(.rateLimited(retryAfter: 120)) {
            try await self.sut.fetchActivities(since: .distantPast)
        }
    }

    func testUnauthorizedExerciseCallSurfacesAsUnauthorized() async throws {
        route(exercisesStatus: 401)
        try await sut.connect(credentials: liveCredentials())

        await assertThrowsConnectorError(.unauthorized) {
            try await self.sut.fetchActivities(since: .distantPast)
        }
    }

    // MARK: - validate

    func testValidateReturnsTrueWhenTheExerciseCallSucceeds() async throws {
        route(exercisesStatus: 204, exercisesBody: "")
        try await sut.connect(credentials: liveCredentials())

        let isValid = try await sut.validate()

        XCTAssertTrue(isValid)
    }

    func testValidateReturnsFalseWhenPolarRejectsTheToken() async throws {
        route(exercisesStatus: 401)
        try await sut.connect(credentials: liveCredentials())

        let isValid = try await sut.validate()

        XCTAssertFalse(isValid)
    }

    func testValidateWithoutCredentialsReturnsFalse() async throws {
        let isValid = try await sut.validate()
        XCTAssertFalse(isValid)
    }

    // MARK: - disconnect

    func testDisconnectClearsTheStoredCredentials() async throws {
        route()
        try await sut.connect(credentials: liveCredentials())

        await sut.disconnect()

        let stored = await sut.currentCredentials()
        XCTAssertNil(stored)
    }
}
