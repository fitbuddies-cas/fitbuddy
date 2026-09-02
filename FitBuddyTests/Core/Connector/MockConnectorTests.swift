import XCTest
@testable import FitBuddy

/// Unit tests for `MockConnector`, proving the test double behaves as
/// configured — this is also the only place today that exercises
/// `FitnessConnector` conformance end to end, ahead of a real `HevyConnector`
/// (#34).
final class MockConnectorTests: XCTestCase {
    func testConnectRecordsTheCredentialsPassedIn() async throws {
        let sut = MockConnector()
        try await sut.connect(credentials: .apiKey("hevy-key"))

        let recorded = await sut.lastConnectedCredentials
        XCTAssertEqual(recorded, .apiKey("hevy-key"))
    }

    func testAFailedConnectLeavesNoConnectedCredentialsBehind() async {
        let sut = MockConnector()
        await sut.setConnectResult(.failure(.unauthorized))

        try? await sut.connect(credentials: .apiKey("bad-key"))

        let connected = await sut.lastConnectedCredentials
        let attempted = await sut.lastAttemptedCredentials
        XCTAssertNil(connected)
        XCTAssertEqual(attempted, .apiKey("bad-key"))
    }

    func testConnectThrowsTheConfiguredError() async {
        let sut = MockConnector()
        await sut.setConnectResult(.failure(.unauthorized))

        do {
            try await sut.connect(credentials: .apiKey("bad-key"))
            XCTFail("Expected .unauthorized to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .unauthorized)
        }
    }

    func testValidateReturnsTheConfiguredResult() async throws {
        let sut = MockConnector()
        await sut.setValidateResult(.success(false))

        let isValid = try await sut.validate()

        XCTAssertFalse(isValid)
    }

    func testFetchActivitiesReturnsTheConfiguredList() async throws {
        let sut = MockConnector()
        let activities = [Activity(id: "a1", title: "Push Day", startTime: .now)]
        await sut.setFetchActivitiesResult(.success(activities))

        let result = try await sut.fetchActivities(since: .distantPast)

        XCTAssertEqual(result, activities)
    }

    func testFetchActivitiesThrowsTheConfiguredError() async {
        let sut = MockConnector()
        await sut.setFetchActivitiesResult(.failure(.networkUnavailable))

        do {
            _ = try await sut.fetchActivities(since: .distantPast)
            XCTFail("Expected .networkUnavailable to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .networkUnavailable)
        }
    }

    func testFetchActivitiesRecordsTheRequestedCutOff() async throws {
        let sut = MockConnector()
        let since = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try await sut.fetchActivities(since: since)

        let recorded = await sut.lastFetchSince
        XCTAssertEqual(recorded, since)
    }

    func testFetchActivitiesReturnsOnlyActivitiesAtOrAfterTheCutOff() async throws {
        let sut = MockConnector()
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let older = Activity(id: "older", title: "Pull Day", startTime: since.addingTimeInterval(-1))
        let atCutOff = Activity(id: "at-cut-off", title: "Push Day", startTime: since)
        let newer = Activity(id: "newer", title: "Leg Day", startTime: since.addingTimeInterval(1))
        await sut.setFetchActivitiesResult(.success([older, atCutOff, newer]))

        let result = try await sut.fetchActivities(since: since)

        XCTAssertEqual(result, [atCutOff, newer])
    }

    func testRecordedCallsAreCountedAndResettable() async throws {
        let sut = MockConnector()
        try await sut.connect(credentials: .apiKey("hevy-key"))
        _ = try await sut.validate()
        _ = try await sut.fetchActivities(since: .distantPast)
        await sut.disconnect()

        var connectCalls = await sut.connectCallCount
        var validateCalls = await sut.validateCallCount
        var fetchCalls = await sut.fetchActivitiesCallCount
        XCTAssertEqual(connectCalls, 1)
        XCTAssertEqual(validateCalls, 1)
        XCTAssertEqual(fetchCalls, 1)

        await sut.resetRecordedCalls()

        connectCalls = await sut.connectCallCount
        validateCalls = await sut.validateCallCount
        fetchCalls = await sut.fetchActivitiesCallCount
        let credentials = await sut.lastConnectedCredentials
        let since = await sut.lastFetchSince
        let didDisconnect = await sut.didDisconnect
        XCTAssertEqual(connectCalls, 0)
        XCTAssertEqual(validateCalls, 0)
        XCTAssertEqual(fetchCalls, 0)
        XCTAssertNil(credentials)
        XCTAssertNil(since)
        XCTAssertFalse(didDisconnect)
    }

    func testDisconnectRecordsThatItWasCalled() async {
        let sut = MockConnector()
        await sut.disconnect()

        let didDisconnect = await sut.didDisconnect
        XCTAssertTrue(didDisconnect)
    }
}
