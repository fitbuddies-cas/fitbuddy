import XCTest
@testable import FitBuddy

/// Unit tests for the `StravaConnector` stub (#35): it conforms to
/// `FitnessConnector` — proven by the compiler and by `testItIsAFitnessConnector`
/// — and refuses every call with `.notImplemented` until v1.
final class StravaConnectorTests: XCTestCase {
    func testItIsAFitnessConnector() {
        let sut: any FitnessConnector = StravaConnector()
        XCTAssertTrue(sut is StravaConnector)
    }

    func testConnectThrowsNotImplemented() async {
        let sut = StravaConnector()
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)

        do {
            try await sut.connect(
                credentials: .oauth(accessToken: "a", refreshToken: "r", expiresAt: expiresAt)
            )
            XCTFail("Expected .notImplemented to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .notImplemented)
        }
    }

    func testValidateThrowsNotImplemented() async {
        let sut = StravaConnector()

        do {
            _ = try await sut.validate()
            XCTFail("Expected .notImplemented to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .notImplemented)
        }
    }

    func testFetchActivitiesThrowsNotImplemented() async {
        let sut = StravaConnector()

        do {
            _ = try await sut.fetchActivities(since: .distantPast)
            XCTFail("Expected .notImplemented to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .notImplemented)
        }
    }

    /// The only call the stub is allowed to complete — a connector that never
    /// took credentials is already disconnected.
    func testDisconnectCompletesWithoutThrowing() async {
        let sut = StravaConnector()
        await sut.disconnect()
    }
}
