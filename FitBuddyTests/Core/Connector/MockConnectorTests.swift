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

    func testDisconnectRecordsThatItWasCalled() async {
        let sut = MockConnector()
        await sut.disconnect()

        let didDisconnect = await sut.didDisconnect
        XCTAssertTrue(didDisconnect)
    }
}
