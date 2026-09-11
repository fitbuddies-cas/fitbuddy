import XCTest
@testable import FitBuddy

/// Unit tests for `StravaOAuthService` (#138, ADR-10). The browser is a
/// `StubWebAuthenticator`, the token endpoint a `StubURLProtocol` — no real
/// network traffic and no sheet.
final class StravaOAuthServiceTests: XCTestCase {
    private var web: StubWebAuthenticator!
    private var sut: StravaOAuthService!

    private let credentials = StravaClientCredentials(clientID: "123456", clientSecret: "s3cr3t")

    override func setUp() {
        super.setUp()
        web = StubWebAuthenticator()
        sut = StravaOAuthService(webAuthenticator: web, session: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        sut = nil
        web = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private static func tokenResponse(
        access: String = "access-1",
        refresh: String = "refresh-1",
        expiresAt: Int = 1_800_000_000,
        for request: URLRequest
    ) -> (HTTPURLResponse, Data) {
        let json = """
        {"token_type":"Bearer","expires_at":\(expiresAt),"expires_in":21600,
         "refresh_token":"\(refresh)","access_token":"\(access)",
         "athlete":{"id":42,"firstname":"Test"}}
        """
        return (Self.http(200, for: request), Data(json.utf8))
    }

    private static func http(_ status: Int, for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    /// `URLProtocol` hands POST bodies over as a stream; read whichever form
    /// is populated and split the form encoding back into pairs.
    private func formBody(of request: URLRequest) throws -> [String: String] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                collected.append(buffer, count: read)
            }
            data = collected
        }
        var pairs: [String: String] = [:]
        for pair in String(decoding: data, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            pairs[parts[0].removingPercentEncoding ?? parts[0]] =
                parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
        }
        return pairs
    }

    private func queryItems(of url: URL) -> [String: String] {
        var result: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            result[item.name] = item.value
        }
        return result
    }

    private func assertAuthorizeThrows(
        _ expected: StravaOAuthError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await sut.authorize(credentials)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as StravaOAuthError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    // MARK: - Authorization request

    func testAuthorizeOpensStravaWithTheExpectedParameters() async throws {
        StubURLProtocol.handler = { Self.tokenResponse(for: $0) }

        _ = try await sut.authorize(credentials)

        let receivedURLs = await web.receivedURLs
        let url = try XCTUnwrap(receivedURLs.first)
        XCTAssertEqual(url.host, "www.strava.com")
        XCTAssertEqual(url.path, "/oauth/authorize")
        let query = queryItems(of: url)
        XCTAssertEqual(query["client_id"], "123456")
        // Strava matches the URI's host against the application's callback
        // domain; the host has to be exactly what the user is told to enter.
        XCTAssertEqual(query["redirect_uri"], "fitbuddy://localhost/strava")
        XCTAssertEqual(URL(string: query["redirect_uri"] ?? "")?.host, StravaKeyPresentation.callbackDomain)
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["approval_prompt"], "auto")
        XCTAssertEqual(query["scope"], "activity:read_all")
        XCTAssertEqual(query["state"]?.count, 64, "state should be 32 random bytes as hex")
        XCTAssertNil(query["client_secret"], "the secret must never appear in the browser URL")

        let scheme = await web.receivedSchemes.first
        XCTAssertEqual(scheme, "fitbuddy")
    }

    /// The state is what proves a callback answers our request; a fixed one
    /// would prove nothing.
    func testEachAuthorizationUsesAFreshState() async throws {
        StubURLProtocol.handler = { Self.tokenResponse(for: $0) }

        _ = try await sut.authorize(credentials)
        _ = try await sut.authorize(credentials)

        let urls = await web.receivedURLs
        XCTAssertEqual(urls.count, 2)
        XCTAssertNotEqual(queryItems(of: urls[0])["state"], queryItems(of: urls[1])["state"])
    }

    // MARK: - Code exchange

    func testAuthorizeExchangesTheCodeWithClientCredentials() async throws {
        nonisolated(unsafe) var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return Self.tokenResponse(for: request)
        }

        let result = try await sut.authorize(credentials)

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "www.strava.com")
        XCTAssertEqual(request.url?.path, "/oauth/token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let form = try formBody(of: request)
        XCTAssertEqual(form["client_id"], "123456")
        XCTAssertEqual(form["client_secret"], "s3cr3t")
        XCTAssertEqual(form["code"], "the-code")
        XCTAssertEqual(form["grant_type"], "authorization_code")

        XCTAssertEqual(
            result,
            .oauth(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        )
    }

    /// A `+` in a form body reads as a space server-side; the encoder must
    /// escape it rather than leave it to `URLComponents`.
    func testFormBodyPercentEncodesReservedCharacters() async throws {
        nonisolated(unsafe) var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return Self.tokenResponse(for: request)
        }
        let awkward = StravaClientCredentials(clientID: "123456", clientSecret: "a+b&c=d/e")

        _ = try await sut.authorize(awkward)

        let form = try formBody(of: try XCTUnwrap(captured))
        XCTAssertEqual(form["client_secret"], "a+b&c=d/e")
        let raw = String(decoding: try XCTUnwrap(captured?.httpBody ?? Data()), as: UTF8.self)
        XCTAssertFalse(raw.contains("a+b"), "raw body must not contain an unescaped '+'")
    }

    // MARK: - Callback validation

    func testMismatchedStateIsRejectedBeforeAnyTokenRequest() async throws {
        await web.set(.callback(URL(string: "fitbuddy://localhost/strava?state=someone-elses&code=the-code&scope=activity:read_all")!))
        nonisolated(unsafe) var tokenRequests = 0
        StubURLProtocol.handler = { request in
            tokenRequests += 1
            return Self.tokenResponse(for: request)
        }

        await assertAuthorizeThrows(.stateMismatch)
        XCTAssertEqual(tokenRequests, 0)
    }

    func testAccessDeniedCallbackThrowsAccessDenied() async {
        await web.set(.fail(error: "access_denied"))
        await assertAuthorizeThrows(.accessDenied)
    }

    func testUnknownErrorCallbackThrowsInvalidCallback() async {
        await web.set(.fail(error: "server_error"))
        await assertAuthorizeThrows(.invalidCallback)
    }

    func testCallbackWithoutCodeThrowsInvalidCallback() async {
        await web.set(.succeed(code: "", scope: "activity:read_all"))
        await assertAuthorizeThrows(.invalidCallback)
    }

    /// The user can untick the scope on Strava's consent page; the callback
    /// then still carries a code that would only ever yield 401s.
    func testCallbackWithoutActivityScopeThrowsMissingScope() async {
        await web.set(.succeed(code: "the-code", scope: "read"))
        await assertAuthorizeThrows(.missingScope)
    }

    func testCallbackWithoutAnyScopeThrowsMissingScope() async {
        await web.set(.succeed(code: "the-code", scope: nil))
        await assertAuthorizeThrows(.missingScope)
    }

    // MARK: - Sheet dismissed / transport

    func testDismissedSheetThrowsCancelledNotTransport() async {
        await web.set(.throw(CancellationError()))
        await assertAuthorizeThrows(.cancelled)
    }

    func testBrowserFailureThrowsTransport() async {
        await web.set(.throw(URLError(.cannotConnectToHost)))
        await assertAuthorizeThrows(.transport)
    }

    func testTokenEndpointTransportFailureThrowsTransport() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertAuthorizeThrows(.transport)
    }

    // MARK: - Token endpoint status mapping

    func testHTTP401OnCodeExchangeThrowsInvalidClientCredentials() async {
        StubURLProtocol.handler = { (Self.http(401, for: $0), Data()) }
        await assertAuthorizeThrows(.invalidClientCredentials)
    }

    func testHTTP400BlamingTheSecretThrowsInvalidClientCredentials() async {
        StubURLProtocol.handler = {
            let body = #"{"message":"Bad Request","errors":[{"resource":"Application","field":"client_secret","code":"invalid"}]}"#
            return (Self.http(400, for: $0), Data(body.utf8))
        }
        await assertAuthorizeThrows(.invalidClientCredentials)
    }

    func testHTTP500ThrowsUnexpectedStatus() async {
        StubURLProtocol.handler = { (Self.http(500, for: $0), Data()) }
        await assertAuthorizeThrows(.unexpectedStatus(500))
    }

    func testUndecodable200ThrowsInvalidResponse() async {
        StubURLProtocol.handler = { (Self.http(200, for: $0), Data("<html>".utf8)) }
        await assertAuthorizeThrows(.invalidResponse)
    }

    // MARK: - Refresh

    func testRefreshSendsTheRefreshGrantAndReturnsTheRotatedToken() async throws {
        nonisolated(unsafe) var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return Self.tokenResponse(access: "access-2", refresh: "refresh-2", expiresAt: 1_800_021_600, for: request)
        }

        let result = try await sut.refresh(credentials, refreshToken: "refresh-1")

        let form = try formBody(of: try XCTUnwrap(captured))
        XCTAssertEqual(form["grant_type"], "refresh_token")
        XCTAssertEqual(form["refresh_token"], "refresh-1")
        XCTAssertEqual(form["client_id"], "123456")
        XCTAssertEqual(form["client_secret"], "s3cr3t")
        XCTAssertNil(form["code"])

        guard case .oauth(let access, let refresh, let expiresAt) = result else {
            return XCTFail("expected oauth credentials")
        }
        XCTAssertEqual(access, "access-2")
        XCTAssertEqual(refresh, "refresh-2", "the rotated refresh token must be returned, not the one submitted")
        XCTAssertEqual(expiresAt, Date(timeIntervalSince1970: 1_800_021_600))

        let browserCalls = await web.receivedURLs.count
        XCTAssertEqual(browserCalls, 0, "a refresh must never open the browser")
    }

    /// Same status as a bad secret, different meaning: during a refresh the
    /// likelier cause is a revoked or already-rotated refresh token.
    func testHTTP400OnRefreshWithoutBlameThrowsInvalidGrant() async {
        StubURLProtocol.handler = {
            let body = #"{"message":"Bad Request","errors":[{"resource":"RefreshToken","field":"refresh_token","code":"invalid"}]}"#
            return (Self.http(400, for: $0), Data(body.utf8))
        }

        do {
            _ = try await sut.refresh(credentials, refreshToken: "revoked")
            XCTFail("expected invalidGrant")
        } catch let error as StravaOAuthError {
            XCTAssertEqual(error, .invalidGrant)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testHTTP400OnRefreshBlamingTheSecretThrowsInvalidClientCredentials() async {
        StubURLProtocol.handler = {
            let body = #"{"errors":[{"resource":"Application","field":"client_secret","code":"invalid"}]}"#
            return (Self.http(400, for: $0), Data(body.utf8))
        }

        do {
            _ = try await sut.refresh(credentials, refreshToken: "refresh-1")
            XCTFail("expected invalidClientCredentials")
        } catch let error as StravaOAuthError {
            XCTAssertEqual(error, .invalidClientCredentials)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - URL scheme

    /// The custom scheme has to be in the built app's Info.plist, or the
    /// callback has nowhere to land. Tests are hosted in FitBuddy.app, so
    /// `Bundle.main` is the app bundle.
    func testCallbackSchemeIsRegisteredInTheAppBundle() throws {
        let urlTypes = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains(StravaOAuthService.callbackScheme), "registered schemes: \(schemes)")
    }
}
