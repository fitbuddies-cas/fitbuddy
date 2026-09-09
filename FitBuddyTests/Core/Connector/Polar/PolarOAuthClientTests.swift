import XCTest
@testable import FitBuddy

final class PolarOAuthClientTests: XCTestCase {
    private let configuration = PolarClientConfiguration(
        clientID: "fitbuddy-client",
        redirectURI: "fitbuddy://polar-oauth"
    )
    private var sut: PolarOAuthClient!
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        sut = PolarOAuthClient(
            configuration: configuration,
            session: StubURLProtocol.makeSession(),
            now: { [epoch] in epoch }
        )
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        sut = nil
        super.tearDown()
    }

    func testAuthorizationURLCarriesPKCEChallengeAndRegisteredClientParameters() async {
        let pkce = PolarPKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        let url = await sut.authorizationURL(pkce: pkce, state: "xyz")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(url.host, "auth.polar.com")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("client_id"), "fitbuddy-client")
        XCTAssertEqual(value("redirect_uri"), "fitbuddy://polar-oauth")
        XCTAssertEqual(value("code_challenge"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("state"), "xyz")
    }

    func testExchangeSendsPKCEVerifierAndPublicClientIDInTheBody() async throws {
        nonisolated(unsafe) var body: String?
        StubURLProtocol.handler = { request in
            body = PolarTestSupport.body(of: request)
            return PolarTestSupport.http(
                200,
                for: request,
                body: #"{"access_token":"at","refresh_token":"rt","expires_in":43199}"#
            )
        }

        let credentials = try await sut.exchange(
            code: "auth-code",
            pkce: PolarPKCE(verifier: "verifier-value")
        )

        let sent = try XCTUnwrap(body)
        XCTAssertTrue(sent.contains("grant_type=authorization_code"))
        XCTAssertTrue(sent.contains("code=auth-code"))
        XCTAssertTrue(sent.contains("code_verifier=verifier-value"))
        XCTAssertTrue(sent.contains("client_id=fitbuddy-client"))
        XCTAssertEqual(
            credentials,
            .oauth(accessToken: "at", refreshToken: "rt", expiresAt: epoch.addingTimeInterval(43_199))
        )
    }

    func testRefreshCarriesTheOldRefreshTokenForwardWhenTheResponseOmitsANewOne() async throws {
        StubURLProtocol.handler = { request in
            PolarTestSupport.http(200, for: request, body: #"{"access_token":"at2","expires_in":100}"#)
        }

        let credentials = try await sut.refresh(refreshToken: "old-rt")

        XCTAssertEqual(
            credentials,
            .oauth(accessToken: "at2", refreshToken: "old-rt", expiresAt: epoch.addingTimeInterval(100))
        )
    }

    func testADeadRefreshTokenComesBackAsUnauthorized() async {
        StubURLProtocol.handler = { request in
            PolarTestSupport.http(400, for: request, body: #"{"error":"invalid_grant"}"#)
        }

        await assertThrowsConnectorError(.unauthorized) {
            try await self.sut.refresh(refreshToken: "dead")
        }
    }

    func testATransportFailureComesBackAsNetworkUnavailable() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        await assertThrowsConnectorError(.networkUnavailable) {
            try await self.sut.exchange(code: "c", pkce: PolarPKCE())
        }
    }
}
