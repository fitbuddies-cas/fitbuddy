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

    private static var renewedPair: ConnectorCredentials {
        .oauth(accessToken: "access-2", refreshToken: "refresh-2", expiresAt: now.addingTimeInterval(6 * 3600))
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

    // MARK: - Stored state

    func testRefreshStoredStateWithoutCredentialsIsMissingCredentialsAndCannotConnect() async {
        store = StubStravaCredentialStore(clientCredentials: nil)
        sut = makeViewModel()

        await sut.refreshStoredState()

        XCTAssertEqual(sut.state, .missingCredentials)
        XCTAssertFalse(sut.canConnect)
        XCTAssertFalse(sut.isConnected)
    }

    func testRefreshStoredStateWithCredentialsButNoPairIsIdle() async {
        await sut.refreshStoredState()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.canConnect)
        XCTAssertFalse(sut.isConnected)
    }

    /// A pair the previous launch stored is handed to the registry, so the
    /// renewal prompt and the sync see the same connection this screen does.
    func testRefreshStoredStateWithAStoredPairConnectsTheRegistry() async {
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.validPair)
        sut = makeViewModel()

        await sut.refreshStoredState()

        XCTAssertEqual(sut.state, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
        XCTAssertTrue(sut.isConnected)
        let registryState = await registry.state(of: .strava, now: Self.now)
        XCTAssertEqual(registryState, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
    }

    func testRefreshStoredStateWithAnExpiredPairIsExpired() async {
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.expiredPair)
        sut = makeViewModel()

        await sut.refreshStoredState()

        XCTAssertEqual(sut.state, .expired(since: Self.now.addingTimeInterval(-3600)))
        XCTAssertTrue(sut.canConnect, "an expired connection is renewed by reconnecting")
        XCTAssertTrue(sut.isConnected, "there is still a pair to disconnect")
    }

    /// A Keychain that refuses the read is not "nothing entered" — the
    /// screen must not tell a fully set-up user to enter credentials again.
    func testRefreshStoredStateReportsAnUnreadableStoreAsAKeychainFailure() async {
        await store.setFailReads(true)

        await sut.refreshStoredState()

        XCTAssertEqual(sut.state, .failed(.keychain))
        XCTAssertTrue(sut.canConnect, "the user can try again once the device is unlocked")
    }

    /// A run-out access token with a good refresh token is the everyday case
    /// (six-hour tokens, US-5 AC4): the connector renews it silently and the
    /// screen reports the renewed pair, not a false alarm.
    func testRefreshStoredStateRenewsAnExpiredPairBeforeReportingIt() async {
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.expiredPair)
        await oauth.setRefreshResult(.success(Self.renewedPair))
        await registry.register(
            StravaConnector(session: StubURLProtocol.makeSession(), oauth: oauth, credentialStore: store, now: { Self.now }),
            for: .strava
        )
        sut = makeViewModel()

        await sut.refreshStoredState()

        XCTAssertEqual(sut.state, .connected(expiresAt: Self.now.addingTimeInterval(6 * 3600)))
        let stored = await store.storedCredentials
        XCTAssertEqual(stored, Self.renewedPair, "the rotated pair is what got persisted")
        let registryState = await registry.state(of: .strava, now: Self.now)
        XCTAssertEqual(registryState, .connected(expiresAt: Self.now.addingTimeInterval(6 * 3600)))
    }

    /// Only a pair Strava actually rejects is reported as expired (US-5 AC2).
    func testRefreshStoredStateKeepsExpiredWhenStravaRejectsTheRefresh() async {
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.expiredPair)
        await oauth.setRefreshResult(.failure(StravaOAuthError.invalidGrant))
        await registry.register(
            StravaConnector(session: StubURLProtocol.makeSession(), oauth: oauth, credentialStore: store, now: { Self.now }),
            for: .strava
        )
        sut = makeViewModel()

        await sut.refreshStoredState()

        XCTAssertEqual(sut.state, .expired(since: Self.now.addingTimeInterval(-3600)))
        XCTAssertTrue(sut.isConnected, "there is still a pair to disconnect")
    }

    /// A pair the connector refreshed in the meantime — and, with a locked
    /// Keychain, may hold nowhere else — is not overwritten by the stale
    /// stored one on the next visit to the screen.
    func testRefreshStoredStateDoesNotOverwriteANewerPairTheRegistryHolds() async throws {
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.validPair)
        sut = makeViewModel()
        try await registry.connect(.strava, credentials: Self.renewedPair)

        await sut.refreshStoredState()

        XCTAssertEqual(sut.state, .connected(expiresAt: Self.now.addingTimeInterval(6 * 3600)))
    }

    /// Returning from the credentials screen after entering a pair.
    func testRefreshStoredStatePicksUpNewlyEnteredCredentials() async {
        store = StubStravaCredentialStore(clientCredentials: nil)
        sut = makeViewModel()
        await sut.refreshStoredState()
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
        await sut.refreshStoredState()

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
        await sut.refreshStoredState()

        await sut.connect()

        XCTAssertEqual(sut.state, .missingCredentials)
        let authorized = await oauth.authorizeCalls.count
        XCTAssertEqual(authorized, 0)
    }

    /// A dismissed sheet is a decision, not a failure: no banner, back to
    /// where the user was.
    func testCancelledFlowReturnsToTheStateBeforeAndShowsNoBanner() async {
        await oauth.setAuthorizeResult(.failure(StravaOAuthError.cancelled))
        await sut.refreshStoredState()

        await sut.connect()

        XCTAssertEqual(sut.state, .idle)
        let stored = await store.storedCredentials
        XCTAssertNil(stored)
    }

    func testCancelledReconnectKeepsTheExistingConnection() async {
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.validPair)
        sut = makeViewModel()
        await oauth.setAuthorizeResult(.failure(StravaOAuthError.cancelled))
        await sut.refreshStoredState()

        await sut.connect()

        XCTAssertEqual(sut.state, .connected(expiresAt: Self.now.addingTimeInterval(4 * 3600)))
    }

    /// AC: wrong client credentials point the user at the credentials screen.
    func testRejectedClientCredentialsPointToTheCredentialsScreen() async {
        await oauth.setAuthorizeResult(.failure(StravaOAuthError.invalidClientCredentials))
        await sut.refreshStoredState()

        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.invalidClientCredentials))
        XCTAssertTrue(StravaConnectionFailure.invalidClientCredentials.pointsToCredentials)
        XCTAssertTrue(sut.canConnect, "the user can try again")
    }

    func testDeclinedConsentIsReportedWithoutPointingToCredentials() async {
        await oauth.setAuthorizeResult(.failure(StravaOAuthError.accessDenied))
        await sut.refreshStoredState()

        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.accessDenied))
        XCTAssertFalse(StravaConnectionFailure.accessDenied.pointsToCredentials)
    }

    func testKeychainFailureAfterAuthorizationIsReportedAndNothingIsConnected() async {
        await oauth.setAuthorizeResult(.success(Self.validPair))
        await store.setFailWrites(true)
        await sut.refreshStoredState()

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
        await sut.refreshStoredState()
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

    /// A Keychain that refuses the delete must not leave a half-torn-down
    /// connection: the cache and the registry are cleared regardless, the
    /// failure is shown, and Disconnect stays on offer so it can be retried.
    func testDisconnectKeychainFailureStillDropsTheCacheAndCanBeRetried() async {
        var notified = 0
        store = StubStravaCredentialStore(clientCredentials: Self.client, credentials: Self.validPair)
        sut = makeViewModel()
        sut.onDisconnected = { notified += 1 }
        await sut.refreshStoredState()
        await store.setFailWrites(true)

        await sut.disconnect()

        XCTAssertEqual(sut.state, .failed(.keychain))
        XCTAssertTrue(sut.isConnected, "the tokens are still stored, so tearing down must be offered again")
        XCTAssertEqual(notified, 1, "the cached sessions are gone, the dashboard has to re-read")
        let discarded = await reset.discardedSources
        XCTAssertEqual(discarded, [.strava])
        let registryState = await registry.state(of: .strava, now: Self.now)
        XCTAssertEqual(registryState, .disconnected)

        await store.setFailWrites(false)
        await sut.disconnect()

        XCTAssertEqual(sut.state, .missingCredentials)
        let cleared = await store.clearCount
        XCTAssertEqual(cleared, 2)
    }

    /// The registry not taking the pair means no connection — and the pair
    /// just stored goes again, or the next sync would pull Strava in under a
    /// screen that says "not connected".
    func testConnectRemovesTheStoredPairWhenTheRegistryRefusesIt() async {
        let refusing = MockConnector()
        await refusing.setConnectResult(.failure(.unauthorized))
        await registry.register(refusing, for: .strava)
        await oauth.setAuthorizeResult(.success(Self.validPair))
        await sut.refreshStoredState()

        await sut.connect()

        XCTAssertEqual(sut.state, .failed(.invalidResponse))
        let stored = await store.storedCredentials
        XCTAssertNil(stored)
        let tokensCleared = await store.clearTokensCount
        XCTAssertEqual(tokensCleared, 1)
        let remainingClient = await store.storedClientCredentials
        XCTAssertEqual(remainingClient, Self.client, "the application credentials were not what failed")
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
