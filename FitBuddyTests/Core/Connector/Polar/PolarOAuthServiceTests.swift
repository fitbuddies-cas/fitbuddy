import XCTest
@testable import FitBuddy

final class PolarOAuthServiceTests: XCTestCase {
    private let configuration = PolarClientConfiguration(
        clientID: "fitbuddy-client",
        redirectURI: "fitbuddy://polar/callback"
    )
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeSUT(
        webAuthenticator: StubWebAuthenticator,
        credentialStore: StubPolarCredentialStore = StubPolarCredentialStore()
    ) -> PolarOAuthService {
        PolarOAuthService(
            configuration: configuration,
            webAuthenticator: webAuthenticator,
            credentialStore: credentialStore,
            session: StubURLProtocol.makeSession()
        )
    }

    func testASuccessfulFlowReturnsCredentialsAndPersistsThemInTheStore() async throws {
        StubURLProtocol.handler = { request in
            PolarTestSupport.http(
                200,
                for: request,
                body: #"{"access_token":"at","refresh_token":"rt","expires_in":43199}"#
            )
        }
        let webAuthenticator = StubWebAuthenticator(.succeed(code: "auth-code", scope: nil))
        let credentialStore = StubPolarCredentialStore()
        let sut = makeSUT(webAuthenticator: webAuthenticator, credentialStore: credentialStore)

        let credentials = try await sut.authorize()

        guard case .oauth(let access, let refresh, _) = credentials else {
            return XCTFail("Expected .oauth credentials")
        }
        XCTAssertEqual(access, "at")
        XCTAssertEqual(refresh, "rt")

        let stored = try await credentialStore.credentials()
        XCTAssertEqual(stored, credentials)
    }

    func testUsesTheRedirectURISchemeAsTheCallbackScheme() async throws {
        StubURLProtocol.handler = { request in
            PolarTestSupport.http(200, for: request, body: #"{"access_token":"at","refresh_token":"rt","expires_in":100}"#)
        }
        let webAuthenticator = StubWebAuthenticator(.succeed(code: "c", scope: nil))
        let sut = makeSUT(webAuthenticator: webAuthenticator)

        _ = try await sut.authorize()

        let scheme = await webAuthenticator.receivedSchemes.first
        XCTAssertEqual(scheme, "fitbuddy")
    }

    func testADismissedSheetComesBackAsCancelled() async {
        let webAuthenticator = StubWebAuthenticator(.throw(CancellationError()))
        let sut = makeSUT(webAuthenticator: webAuthenticator)

        do {
            _ = try await sut.authorize()
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
            _ = try await sut.authorize()
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
            _ = try await sut.authorize()
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
            try await sut.authorize()
        }
    }

    func testAFailingCredentialStoreSurfacesItsError() async {
        StubURLProtocol.handler = { request in
            PolarTestSupport.http(200, for: request, body: #"{"access_token":"at","refresh_token":"rt","expires_in":100}"#)
        }
        let webAuthenticator = StubWebAuthenticator(.succeed(code: "c", scope: nil))
        let credentialStore = StubPolarCredentialStore()
        await credentialStore.setFailWrites(true)
        let sut = makeSUT(webAuthenticator: webAuthenticator, credentialStore: credentialStore)

        do {
            _ = try await sut.authorize()
            XCTFail("Expected the credential store's error to propagate")
        } catch is StubPolarCredentialStore.Failure {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
