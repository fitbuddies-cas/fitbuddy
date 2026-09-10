import XCTest
@testable import FitBuddy

/// Unit tests for `StravaConnectionViewModel` (#140, US-5 AC1). The OAuth
/// service and the credential store are the in-memory doubles; the registry
/// is the real one with a real `StravaConnector` (built on doubles) behind
/// `.strava`, because the hand-over to the registry is what this type is for.
@MainActor
final class StravaConnectionViewModelTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_754_400_000)
    private static let client = StravaClientCredentials(clientID: "123456", clientSecret: "s3cr3t")

    private var oauth: StubStravaOAuthorizer!
    private var store: StubStravaCredentialStore!
    private var registry: ConnectorRegistry!
    private var reset: SessionResetSpy!
    private var sut: StravaConnectionViewModel!

    private static var validPair: ConnectorCredentials {
        .oauth(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: now.addingTimeInterval(4 * 3600))
    }

    private static var expiredPair: ConnectorCredentials {
        .oauth(accessToken: "access-old", refreshToken: "refresh-old", expiresAt: now.addingTimeInterval(-3600))
    }

    override func setUp() async throws {
        try await super.setUp()
        oauth = StubStravaOAuthorizer()
        store = StubStravaCredentialStore(clientCredentials: Self.client)
        registry = ConnectorRegistry()
        reset = SessionResetSpy()
        await registry.register(
            StravaConnector(session: StubURLProtocol.makeSession(), oauth: oauth, credentialStore: store),
            for: .strava
        )
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

    private func makeViewModel() -> StravaConnectionViewModel {
        StravaConnectionViewModel(
            oauth: oauth,
            credentialStore: store,
            registry: registry,
            sessionReset: reset,
            now: { Self.now }
        )
    }

    // MARK: - Bootstrap

    func testBootstrapWithoutCredentialsIsMissingCredentialsAndCannotConnect() async {
        store = StubStravaCredentialStore(clientCredentials: nil)
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

    /// A pair the previous launch stored is handed to the registry, so the
    /// renewal prompt and the sync see the same connection this screen does.
    func testBootstrapWithAStoredPairConnectsTheRegistry() async {
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.validPair)
        sut = makeViewModel()

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
        XCTAssertTrue(sut.isConnected)
        let registryState = await registry.state(of: .strava, now: Self.now)
        XCTAssertEqual(registryState, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
    }

    func testBootstrapWithAnExpiredPairIsExpired() async {
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.expiredPair)
        sut = makeViewModel()

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .expired(since: Self.now.addingTimeInterval(-3600)))
        XCTAssertTrue(sut.canConnect, "an expired connection is renewed by reconnecting")
        XCTAssertTrue(sut.isConnected, "there is still a pair to disconnect")
    }

    func testBootstrapFailsOpenWhenTheStoreCannotBeRead() async {
        await store.setFailReads(true)

        await sut.bootstrap()

        XCTAssertEqual(sut.state, .missingCredentials)
    }

    /// Returning from the credentials screen after entering a pair.
    func testRefreshStoredStatePicksUpNewlyEnteredCredentials() async {
        store = StubStravaCredentialStore(clientCredentials: nil)
        sut = makeViewModel()
        await sut.bootstrap()
        XCTAssertEqual(sut.state, .missingCredentials)

        try? await store.saveClientCredentials(Self.client)
        await sut.refreshStoredState()

        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Connect

    func testConnectStoresThePairConnectsTheRegistryAndNotifies() async {
        var notified = 0
        sut.onConnected = { notified += 1 }
        await oauth.setAuthorizeResult(.success(Self.validPair))
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
        XCTAssertEqual(notified, 1)
        let authorized = await oauth.authorizeCalls
        XCTAssertEqual(authorized, [Self.client])
        let stored = await store.storedCredentials
        XCTAssertEqual(stored, Self.validPair)
        let registryState = await registry.state(of: .strava, now: Self.now)
        XCTAssertEqual(registryState, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
    }

    func testConnectWithoutCredentialsDoesNotOpenTheBrowser() async {
        store = StubStravaCredentialStore(clientCredentials: nil)
        sut = makeViewModel()
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .missingCredentials)
        let authorized = await oauth.authorizeCalls.count
        XCTAssertEqual(authorized, 0)
    }

    /// A dismissed sheet is a decision, not a failure: no banner, back to
    /// where the user was.
    func testCancelledFlowReturnsToTheStateBeforeAndShowsNoBanner() async {
        await oauth.setAuthorizeResult(.failure(StravaOAuthError.cancelled))
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .idle)
        let stored = await store.storedCredentials
        XCTAssertNil(stored)
    }

    func testCancelledReconnectKeepsTheExistingConnection() async {
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.validPair)
        sut = makeViewModel()
        await oauth.setAuthorizeResult(.failure(StravaOAuthError.cancelled))
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
    }

    /// AC: wrong client credentials point the user at the credentials screen.
    func testRejectedClientCredentialsPointToTheCredentialsScreen() async {
        await oauth.setAuthorizeResult(.failure(StravaOAuthError.invalidClientCredentials))
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.invalidClientCredentials))
        XCTAssertTrue(StravaConnectionFailure.invalidClientCredentials.pointsToCredentials)
        XCTAssertTrue(sut.canConnect, "the user can try again")
    }

    func testDeclinedConsentIsReportedWithoutPointingToCredentials() async {
        await oauth.setAuthorizeResult(.failure(StravaOAuthError.accessDenied))
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.accessDenied))
        XCTAssertFalse(StravaConnectionFailure.accessDenied.pointsToCredentials)
    }

    func testKeychainFailureAfterAuthorizationIsReportedAndNothingIsConnected() async {
        await oauth.setAuthorizeResult(.success(Self.validPair))
        await store.setFailWrites(true)
        await sut.bootstrap()

        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.keychain))
        let registryState = await registry.state(of: .strava, now: Self.now)
        XCTAssertEqual(registryState, .disconnected, "a pair that was not stored must not be connected")
    }

    // MARK: - Disconnect

    /// AC: every Strava item leaves the Keychain and the Strava sessions leave
    /// the cache; the Hevy session is not touched.
    func testDisconnectClearsEverythingStravaAndNotifies() async {
        var notified = 0
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.validPair)
        sut = makeViewModel()
        sut.onDisconnected = { notified += 1 }
        await sut.bootstrap()
        XCTAssertTrue(sut.isConnected)

        await sut.disconnect()

        XCTAssertEqual(sut.state, .missingCredentials)
        XCTAssertEqual(notified, 1)
        let cleared = await store.clearCount
        XCTAssertEqual(cleared, 1)
        let remainingClient = await store.storedClientCredentials
        XCTAssertNil(remainingClient)
        let registryState = await registry.state(of: .strava, now: Self.now)
        XCTAssertEqual(registryState, .disconnected)
        let discarded = await reset.discardedSources
        XCTAssertEqual(discarded, [.strava])
        let hardLogouts = await reset.hardLogoutCount
        XCTAssertEqual(hardLogouts, 0, "disconnecting Strava must not log out of Hevy")
    }

    func testDisconnectKeychainFailureIsReported() async {
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.validPair)
        sut = makeViewModel()
        await sut.bootstrap()
        await store.setFailWrites(true)

        await sut.disconnect()

        XCTAssertEqual(sut.state, .failed(.keychain))
    }

    // MARK: - Failure presentation

    func testEveryOAuthErrorExceptCancellationHasABanner() {
        let errors: [StravaOAuthError] = [
            .accessDenied, .stateMismatch, .missingScope, .invalidCallback,
            .invalidClientCredentials, .invalidGrant, .invalidResponse, .transport, .unexpectedStatus(500),
        ]
        for error in errors {
            XCTAssertNotNil(StravaConnectionFailure(error), "\(error) should have a banner")
        }
        XCTAssertNil(StravaConnectionFailure(.cancelled))
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
