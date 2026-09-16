import XCTest
@testable import FitBuddy

/// Unit tests for `PolarConnectionViewModel` (#157, US-5 AC1). The OAuth service and the credential store are the
/// in-memory doubles; the registry is the real one with a real
/// `PolarConnector` (built on doubles) behind `.polar`, because the hand-over
/// to the registry is what this type is for.
@MainActor
final class PolarConnectionViewModelTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_754_400_000)

    private var oauth: StubPolarOAuthorizer!
    private var store: StubPolarCredentialStore!
    private var registry: ConnectorRegistry!
    private var reset: SessionResetSpy!
    private var sut: PolarConnectionViewModel!

    private static let clientCredentials = PolarClientCredentials(clientID: "client-1", clientSecret: "secret-1")

    private static var validPair: ConnectorCredentials {
        .oauth(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: now.addingTimeInterval(4 * 3600))
    }

    private static var expiredPair: ConnectorCredentials {
        .oauth(accessToken: "access-old", refreshToken: "refresh-old", expiresAt: now.addingTimeInterval(-3600))
    }

    override func setUp() async throws {
        try await super.setUp()
        oauth = StubPolarOAuthorizer()
        store = StubPolarCredentialStore(clientCredentials: Self.clientCredentials)
        registry = ConnectorRegistry()
        reset = SessionResetSpy()
        await registry.register(makePolarConnector(), for: .polar)
        sut = makeViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        reset = nil
        registry = nil
        store = nil
        oauth = nil
        try await super.tearDown()
    }

    private func makeViewModel() -> PolarConnectionViewModel {
        PolarConnectionViewModel(
            oauth: oauth,
            credentialStore: store,
            registry: registry,
            sessionReset: reset,
            now: { Self.now }
        )
    }

    private func makePolarConnector() -> PolarConnector {
        PolarConnector(
            accessLink: PolarAccessLinkClient(session: StubURLProtocol.makeSession()),
            oauth: StubPolarOAuthorizer(),
            credentialStore: StubPolarCredentialStore(),
            memberID: "test-member"
        )
    }

    // MARK: - Bootstrap

    func testBootstrapWithNoClientCredentialsIsMissingCredentials() async {
        store = StubPolarCredentialStore()
        sut = makeViewModel()

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .missingCredentials)
        XCTAssertFalse(sut.canConnect)
        XCTAssertFalse(sut.isConnected)
    }

    func testBootstrapWithCredentialsButNoPairIsIdle() async {
        await sut.bootstrap()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.canConnect)
        XCTAssertFalse(sut.isConnected)
    }

    /// A pair a previous launch stored is handed to the registry, so the
    /// renewal prompt and the sync see the same connection this screen does.
    func testBootstrapWithAStoredPairConnectsTheRegistry() async {
        store = StubPolarCredentialStore(clientCredentials: Self.clientCredentials, credentials: Self.validPair)
        sut = makeViewModel()

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
        XCTAssertTrue(sut.isConnected)
        let registryState = await registry.state(of: .polar, now: Self.now)
        XCTAssertEqual(registryState, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
    }

    func testBootstrapWithAnExpiredPairIsExpired() async {
        store = StubPolarCredentialStore(clientCredentials: Self.clientCredentials, credentials: Self.expiredPair)
        sut = makeViewModel()

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .expired(since: Self.now.addingTimeInterval(-3600)))
        XCTAssertTrue(sut.canConnect, "an expired connection is renewed by reconnecting")
        XCTAssertTrue(sut.isConnected, "there is still a pair to disconnect")
    }

    // MARK: - Connect

    /// This view model persists the pair itself, like Strava's.
    func testConnectStoresThePairConnectsTheRegistryAndNotifies() async {
        var notified = 0
        sut.onConnected = { notified += 1 }
        await oauth.setAuthorizeResult(.success(Self.validPair))
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
        XCTAssertEqual(notified, 1)
        let authorized = await oauth.authorizeCallCount
        XCTAssertEqual(authorized, 1)
        let stored = try? await store.credentials()
        XCTAssertEqual(stored, Self.validPair)
        let registryState = await registry.state(of: .polar, now: Self.now)
        XCTAssertEqual(registryState, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
    }

    /// A dismissed sheet is a decision, not a failure: no banner, back to
    /// where the user was.
    func testCancelledFlowReturnsToTheStateBeforeAndShowsNoBanner() async {
        await oauth.setAuthorizeResult(.failure(PolarOAuthError.cancelled))
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .idle)
    }

    func testCancelledReconnectKeepsTheExistingConnection() async {
        store = StubPolarCredentialStore(clientCredentials: Self.clientCredentials, credentials: Self.validPair)
        sut = makeViewModel()
        await oauth.setAuthorizeResult(.failure(PolarOAuthError.cancelled))
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
    }

    func testDeclinedConsentIsReportedAsAccessDenied() async {
        await oauth.setAuthorizeResult(.failure(PolarOAuthError.accessDenied))
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.accessDenied))
    }

    func testATokenEndpointRejectionIsReportedAsUnauthorized() async {
        await oauth.setAuthorizeResult(.failure(ConnectorError.unauthorized))
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.unauthorized))
    }

    func testConnectWithoutStoredCredentialsIsMissingCredentials() async {
        store = StubPolarCredentialStore()
        sut = makeViewModel()
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .missingCredentials)
        let authorized = await oauth.authorizeCallCount
        XCTAssertEqual(authorized, 0)
    }

    // MARK: - Disconnect

    /// AC: every Polar item leaves the Keychain and the Polar sessions leave
    /// the cache; the other sources are not touched.
    func testDisconnectClearsEverythingPolarAndNotifies() async {
        var notified = 0
        store = StubPolarCredentialStore(clientCredentials: Self.clientCredentials, credentials: Self.validPair)
        sut = makeViewModel()
        sut.onDisconnected = { notified += 1 }
        await sut.bootstrap()
        XCTAssertTrue(sut.isConnected)

        await sut.disconnect()

        XCTAssertEqual(sut.state, .missingCredentials)
        XCTAssertEqual(notified, 1)
        let cleared = await store.clearCount
        XCTAssertEqual(cleared, 1)
        let registryState = await registry.state(of: .polar, now: Self.now)
        XCTAssertEqual(registryState, .disconnected)
        let discarded = await reset.discardedSources
        XCTAssertEqual(discarded, [.polar])
        let hardLogouts = await reset.hardLogoutCount
        XCTAssertEqual(hardLogouts, 0, "disconnecting Polar must not log out of Hevy")
    }

    func testDisconnectKeychainFailureIsReported() async {
        store = StubPolarCredentialStore(clientCredentials: Self.clientCredentials, credentials: Self.validPair)
        sut = makeViewModel()
        await sut.bootstrap()
        await store.setFailWrites(true)

        await sut.disconnect()

        XCTAssertEqual(sut.state, .failed(.keychain))
    }

    // MARK: - Failure presentation

    func testEveryOAuthErrorExceptCancellationHasABanner() {
        let errors: [PolarOAuthError] = [.accessDenied, .stateMismatch, .invalidCallback, .transport]
        for error in errors {
            XCTAssertNotNil(PolarConnectionFailure(error), "\(error) should have a banner")
        }
        XCTAssertNil(PolarConnectionFailure(.cancelled))
    }
}

/// Records what the reset service was asked to drop.
private actor SessionResetSpy: SessionResetting {
    private(set) var hardLogoutCount = 0
    private(set) var discardedSources: [ConnectorSource] = []

    func hardLogout() async {
        hardLogoutCount += 1
    }

    func discardCachedWorkouts() async {
        discardedSources.append(.hevy)
    }

    func discardCachedWorkouts(from source: ConnectorSource) async {
        discardedSources.append(source)
    }
}
