import XCTest
@testable import FitBuddy

/// `PolarOAuthService` takes the user's application credentials on every call
/// and persists nothing itself — that is `PolarConnectionViewModel`'s job.
final class PolarOAuthServiceTests: XCTestCase {
    private let credentials = PolarClientCredentials(clientID: "fitbuddy-client", clientSecret: "s3cr3t")
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeSUT(webAuthenticator: StubWebAuthenticator) -> PolarOAuthService {
        PolarOAuthService(webAuthenticator: webAuthenticator, session: StubURLProtocol.makeSession())
    }

    func testASuccessfulFlowReturnsCredentials() async throws {
        StubURLProtocol.handler = { request in
            PolarTestSupport.http(
                200,
                for: request,
                body: #"{"access_token":"at","refresh_token":"rt","expires_in":43199}"#
            )
        }
        let webAuthenticator = StubWebAuthenticator(.succeed(code: "auth-code", scope: nil))
        let sut = makeSUT(webAuthenticator: webAuthenticator)

        let credentials = try await sut.authorize(self.credentials)

        guard case .oauth(let access, let refresh, _) = credentials else {
            return XCTFail("Expected .oauth credentials")
        }
        XCTAssertEqual(access, "at")
        XCTAssertEqual(refresh, "rt")
    }

    func testUsesTheFixedRedirectSchemeAsTheCallbackScheme() async throws {
        StubURLProtocol.handler = { request in
            PolarTestSupport.http(200, for: request, body: #"{"access_token":"at","refresh_token":"rt","expires_in":100}"#)
        }
        let webAuthenticator = StubWebAuthenticator(.succeed(code: "c", scope: nil))
        let sut = makeSUT(webAuthenticator: webAuthenticator)

        _ = try await sut.authorize(credentials)

        let scheme = await webAuthenticator.receivedSchemes.first
        XCTAssertEqual(scheme, "fitbuddy")
    }

    func testADismissedSheetComesBackAsCancelled() async {
        let webAuthenticator = StubWebAuthenticator(.throw(CancellationError()))
        let sut = makeSUT(webAuthenticator: webAuthenticator)

        do {
            _ = try await sut.authorize(credentials)
            XCTFail("Expected PolarOAuthError.cancelled")
        } catch let error as PolarOAuthError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAMismatchedStateIsRejectedBeforeReadingAnythingElseFromTheCallback() async {
        let webAuthenticator = StubWebAuthenticator(
            .callback(URL(string: "fitbuddy://polar/callback?state=not-ours&code=stolen")!)
        )
        let sut = makeSUT(webAuthenticator: webAuthenticator)

        do {
            _ = try await sut.authorize(credentials)
            XCTFail("Expected PolarOAuthError.stateMismatch")
        } catch let error as PolarOAuthError {
            XCTAssertEqual(error, .stateMismatch)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUserDeclinedOnThePolarConsentPageComesBackAsAccessDenied() async {
        let webAuthenticator = StubWebAuthenticator(.fail(error: "access_denied"))
        let sut = makeSUT(webAuthenticator: webAuthenticator)

        do {
            _ = try await sut.authorize(credentials)
            XCTFail("Expected PolarOAuthError.accessDenied")
        } catch let error as PolarOAuthError {
            XCTAssertEqual(error, .accessDenied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testATokenEndpointRejectionSurfacesAsConnectorError() async {
        StubURLProtocol.handler = { request in
            PolarTestSupport.http(400, for: request, body: #"{"error":"invalid_grant"}"#)
        }
        let webAuthenticator = StubWebAuthenticator(.succeed(code: "auth-code", scope: nil))
        let sut = makeSUT(webAuthenticator: webAuthenticator)

        await assertThrowsConnectorError(.unauthorized) {
            try await sut.authorize(self.credentials)
        }
    }

    func testRefreshAuthenticatesWithTheGivenCredentials() async throws {
        nonisolated(unsafe) var authorizationHeader: String?
        StubURLProtocol.handler = { request in
            authorizationHeader = request.value(forHTTPHeaderField: "Authorization")
            return PolarTestSupport.http(200, for: request, body: #"{"access_token":"at2","expires_in":100}"#)
        }
        let sut = makeSUT(webAuthenticator: StubWebAuthenticator(.throw(CancellationError())))

        _ = try await sut.refresh(credentials, refreshToken: "old-rt")

        let expectedAuth = "Basic " + Data("fitbuddy-client:s3cr3t".utf8).base64EncodedString()
        XCTAssertEqual(authorizationHeader, expectedAuth)
    }
}
