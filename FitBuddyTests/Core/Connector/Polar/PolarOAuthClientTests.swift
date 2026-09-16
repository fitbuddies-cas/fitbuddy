import XCTest
@testable import FitBuddy

final class PolarOAuthClientTests: XCTestCase {
    private let credentials = PolarClientCredentials(clientID: "fitbuddy-client", clientSecret: "s3cr3t")
    private var sut: PolarOAuthClient!
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        sut = PolarOAuthClient(
            credentials: credentials,
            session: StubURLProtocol.makeSession(),
            now: { [epoch] in epoch }
        )
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        sut = nil
        super.tearDown()
    }

    /// Nachtrag zu ADR-11: AccessLink v3's authorization endpoint is
    /// `flow.polar.com`, not the unrelated v4 `auth.polar.com` host, and it
    /// does not document a PKCE parameter.
    func testAuthorizationURLCarriesRegisteredClientParametersOnTheV3Host() async {
        let url = await sut.authorizationURL(state: "xyz")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(url.host, "flow.polar.com")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("client_id"), "fitbuddy-client")
        XCTAssertEqual(value("redirect_uri"), "fitbuddy://polar/callback")
        XCTAssertEqual(value("state"), "xyz")
    }

    /// Nachtrag zu ADR-11: every token request authenticates via HTTP Basic
    /// `clientID:clientSecret` — there is no public-client fallback any more.
    func testExchangeAuthenticatesWithHTTPBasicOnTheV3TokenHost() async throws {
        nonisolated(unsafe) var body: String?
        nonisolated(unsafe) var authorizationHeader: String?
        nonisolated(unsafe) var requestedHost: String?
        StubURLProtocol.handler = { request in
            body = PolarTestSupport.body(of: request)
            authorizationHeader = request.value(forHTTPHeaderField: "Authorization")
            requestedHost = request.url?.host
            return PolarTestSupport.http(
                200,
                for: request,
                body: #"{"access_token":"at","refresh_token":"rt","expires_in":43199}"#
            )
        }

        let credentials = try await sut.exchange(code: "auth-code")

        let sent = try XCTUnwrap(body)
        XCTAssertTrue(sent.contains("grant_type=authorization_code"))
        XCTAssertTrue(sent.contains("code=auth-code"))
        XCTAssertFalse(sent.contains("code_verifier="), "AccessLink v3 does not support PKCE")
        XCTAssertFalse(sent.contains("client_id="), "the client id travels via HTTP Basic, not the body")
        XCTAssertEqual(requestedHost, "polarremote.com")
        let expectedAuth = "Basic " + Data("fitbuddy-client:s3cr3t".utf8).base64EncodedString()
        XCTAssertEqual(authorizationHeader, expectedAuth)
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
            try await self.sut.exchange(code: "c")
        }
    }
}
