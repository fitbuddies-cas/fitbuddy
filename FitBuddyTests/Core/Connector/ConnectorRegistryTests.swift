import XCTest
@testable import FitBuddy

/// Unit tests for `ConnectorRegistry` (#35): managing several connectors at
/// once, and the credential-expiry bookkeeping US-5 AC2's renewal prompt reads.
final class ConnectorRegistryTests: XCTestCase {
    private let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)
    private var beforeExpiry: Date { expiresAt.addingTimeInterval(-1) }
    private var afterExpiry: Date { expiresAt.addingTimeInterval(1) }

    // MARK: - Registration

    func testItManagesSeveralConnectorsAtOnce() async {
        let sut = ConnectorRegistry()
        let hevy = MockConnector()
        let strava = makeStravaConnector()

        await sut.register(hevy, for: .hevy)
        await sut.register(strava, for: .strava)

        let sources = await sut.registeredSources
        XCTAssertEqual(sources, [.hevy, .strava])
    }

    func testRegisteredSourcesIsEmptyForAFreshRegistry() async {
        let sut = ConnectorRegistry()

        let sources = await sut.registeredSources
        XCTAssertTrue(sources.isEmpty)
    }

    func testConnectorForReturnsTheInstanceThatWasRegistered() async {
        let sut = ConnectorRegistry()
        let hevy = MockConnector()
        await sut.register(hevy, for: .hevy)

        let resolved = await sut.connector(for: .hevy)

        XCTAssertIdentical(resolved as? MockConnector, hevy)
    }

    func testConnectorForAnUnregisteredSourceIsNil() async {
        let sut = ConnectorRegistry()
        await sut.register(MockConnector(), for: .hevy)

        let resolved = await sut.connector(for: .strava)

        XCTAssertNil(resolved)
    }

    /// A replacement connector holds none of the old one's credentials, so the
    /// registry must not keep reporting the source as connected.
    func testRegisteringOverAConnectedSourceResetsItToDisconnected() async throws {
        let sut = ConnectorRegistry()
        await sut.register(MockConnector(), for: .hevy)
        try await sut.connect(.hevy, credentials: .apiKey("hevy-key"))

        await sut.register(MockConnector(), for: .hevy)

        let state = await sut.state(of: .hevy)
        XCTAssertEqual(state, .disconnected)
    }

    func testUnregisterRemovesAndDisconnectsTheConnector() async throws {
        let sut = ConnectorRegistry()
        let hevy = MockConnector()
        await sut.register(hevy, for: .hevy)
        try await sut.connect(.hevy, credentials: .apiKey("hevy-key"))

        await sut.unregister(.hevy)

        let sources = await sut.registeredSources
        let didDisconnect = await hevy.didDisconnect
        let state = await sut.state(of: .hevy)
        XCTAssertTrue(sources.isEmpty)
        XCTAssertTrue(didDisconnect)
        XCTAssertEqual(state, .disconnected)
    }

    func testUnregisteringAnUnknownSourceIsANoOp() async {
        let sut = ConnectorRegistry()
        await sut.register(MockConnector(), for: .hevy)

        await sut.unregister(.strava)

        let sources = await sut.registeredSources
        XCTAssertEqual(sources, [.hevy])
    }

    // MARK: - Connection lifecycle

    func testConnectForwardsTheCredentialsToTheConnector() async throws {
        let sut = ConnectorRegistry()
        let hevy = MockConnector()
        await sut.register(hevy, for: .hevy)

        try await sut.connect(.hevy, credentials: .apiKey("hevy-key"))

        let recorded = await hevy.lastConnectedCredentials
        XCTAssertEqual(recorded, .apiKey("hevy-key"))
    }

    func testConnectOnAnUnregisteredSourceThrowsNotRegistered() async {
        let sut = ConnectorRegistry()

        do {
            try await sut.connect(.strava, credentials: .apiKey("key"))
            XCTFail("Expected .notRegistered to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorRegistryError, .notRegistered(.strava))
        }
    }

    /// The registry must not claim a connection the connector refused —
    /// otherwise the dashboard would sync against credentials that were never
    /// accepted.
    func testARejectedConnectLeavesTheSourceDisconnected() async {
        let sut = ConnectorRegistry()
        let hevy = MockConnector()
        await hevy.setConnectResult(.failure(.unauthorized))
        await sut.register(hevy, for: .hevy)

        do {
            try await sut.connect(.hevy, credentials: .apiKey("bad-key"))
            XCTFail("Expected .unauthorized to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .unauthorized)
        }

        let state = await sut.state(of: .hevy)
        XCTAssertEqual(state, .disconnected)
    }

    /// The real `StravaConnector` (#142) accepts an OAuth pair, and the
    /// registry records the expiry that pair carries — the data behind the
    /// renewal prompt (US-5 AC2).
    func testConnectingStravaRecordsTheTokenExpiry() async throws {
        let sut = ConnectorRegistry()
        await sut.register(makeStravaConnector(), for: .strava)

        try await sut.connect(
            .strava,
            credentials: .oauth(accessToken: "a", refreshToken: "r", expiresAt: expiresAt)
        )

        let state = await sut.state(of: .strava, now: beforeExpiry)
        XCTAssertEqual(state, .connected(expiresAt: expiresAt))
    }

    /// Credentials the connector refuses leave the source disconnected — the
    /// registry does not record a connection the provider never accepted.
    func testConnectingStravaWithAnAPIKeyIsRejectedAndLeavesItDisconnected() async {
        let sut = ConnectorRegistry()
        await sut.register(makeStravaConnector(), for: .strava)

        do {
            try await sut.connect(.strava, credentials: .apiKey("hv_live_abc"))
            XCTFail("Expected .unauthorized to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorError, .unauthorized)
        }

        let state = await sut.state(of: .strava)
        XCTAssertEqual(state, .disconnected)
    }

    /// A Strava connector with doubles for the OAuth service and the
    /// credential store, since the real ones need a browser and a Keychain.
    private func makeStravaConnector() -> StravaConnector {
        StravaConnector(
            session: StubURLProtocol.makeSession(),
            oauth: StubStravaOAuthorizer(),
            credentialStore: StubStravaCredentialStore()
        )
    }

    func testValidateForwardsToTheConnector() async throws {
        let sut = ConnectorRegistry()
        let hevy = MockConnector()
        await hevy.setValidateResult(.success(false))
        await sut.register(hevy, for: .hevy)

        let isValid = try await sut.validate(.hevy)

        let calls = await hevy.validateCallCount
        XCTAssertFalse(isValid)
        XCTAssertEqual(calls, 1)
    }

    func testValidateOnAnUnregisteredSourceThrowsNotRegistered() async {
        let sut = ConnectorRegistry()

        do {
            _ = try await sut.validate(.hevy)
            XCTFail("Expected .notRegistered to be thrown")
        } catch {
            XCTAssertEqual(error as? ConnectorRegistryError, .notRegistered(.hevy))
        }
    }

    func testDisconnectForwardsToTheConnectorAndClearsTheState() async throws {
        let sut = ConnectorRegistry()
        let hevy = MockConnector()
        await sut.register(hevy, for: .hevy)
        try await sut.connect(.hevy, credentials: .apiKey("hevy-key"))

        await sut.disconnect(.hevy)

        let didDisconnect = await hevy.didDisconnect
        let state = await sut.state(of: .hevy)
        let sources = await sut.registeredSources
        XCTAssertTrue(didDisconnect)
        XCTAssertEqual(state, .disconnected)
        XCTAssertEqual(sources, [.hevy], "disconnect keeps the connector registered")
    }

    func testDisconnectingAnUnknownSourceIsANoOp() async {
        let sut = ConnectorRegistry()

        await sut.disconnect(.strava)

        let state = await sut.state(of: .strava)
        XCTAssertEqual(state, .disconnected)
    }

    // MARK: - Expiry

    func testAConnectedAPIKeySourceNeverExpires() async throws {
        let sut = ConnectorRegistry()
        await sut.register(MockConnector(), for: .hevy)

        try await sut.connect(.hevy, credentials: .apiKey("hevy-key"))

        let state = await sut.state(of: .hevy, now: .distantFuture)
        XCTAssertEqual(state, .connected(expiresAt: nil))
    }

    func testAnOAuthSourceStaysConnectedUntilItsTokenRunsOut() async throws {
        let sut = ConnectorRegistry()
        await sut.register(MockConnector(), for: .strava)

        try await sut.connect(
            .strava,
            credentials: .oauth(accessToken: "a", refreshToken: "r", expiresAt: expiresAt)
        )

        let state = await sut.state(of: .strava, now: beforeExpiry)
        XCTAssertEqual(state, .connected(expiresAt: expiresAt))
        XCTAssertFalse(state.needsRenewal)
    }

    func testAnOAuthSourceIsExpiredOnceItsTokenRanOut() async throws {
        let sut = ConnectorRegistry()
        await sut.register(MockConnector(), for: .strava)

        try await sut.connect(
            .strava,
            credentials: .oauth(accessToken: "a", refreshToken: "r", expiresAt: expiresAt)
        )

        let state = await sut.state(of: .strava, now: afterExpiry)
        XCTAssertEqual(state, .expired(since: expiresAt))
        XCTAssertTrue(state.needsRenewal)
    }

    /// A token whose expiry is exactly now would be rejected by the very next
    /// request — the registry prompts rather than syncing into a 401.
    func testATokenExpiringExactlyNowCountsAsExpired() async throws {
        let sut = ConnectorRegistry()
        await sut.register(MockConnector(), for: .strava)

        try await sut.connect(
            .strava,
            credentials: .oauth(accessToken: "a", refreshToken: "r", expiresAt: expiresAt)
        )

        let state = await sut.state(of: .strava, now: expiresAt)
        XCTAssertEqual(state, .expired(since: expiresAt))
    }

    func testSourcesNeedingRenewalListsOnlyTheExpiredOnes() async throws {
        let sut = ConnectorRegistry()
        await sut.register(MockConnector(), for: .hevy)
        await sut.register(MockConnector(), for: .strava)
        try await sut.connect(.hevy, credentials: .apiKey("hevy-key"))
        try await sut.connect(
            .strava,
            credentials: .oauth(accessToken: "a", refreshToken: "r", expiresAt: expiresAt)
        )

        let renewals = await sut.sourcesNeedingRenewal(now: afterExpiry)

        XCTAssertEqual(renewals, [.strava])
    }

    func testSourcesNeedingRenewalIsEmptyWhileEveryTokenIsStillValid() async throws {
        let sut = ConnectorRegistry()
        await sut.register(MockConnector(), for: .strava)
        try await sut.connect(
            .strava,
            credentials: .oauth(accessToken: "a", refreshToken: "r", expiresAt: expiresAt)
        )

        let renewals = await sut.sourcesNeedingRenewal(now: beforeExpiry)

        XCTAssertTrue(renewals.isEmpty)
    }

    /// A disconnected source has nothing to renew — the prompt belongs to
    /// «your connection ran out», not to «you never connected».
    func testADisconnectedSourceIsNotListedForRenewal() async throws {
        let sut = ConnectorRegistry()
        await sut.register(MockConnector(), for: .strava)
        try await sut.connect(
            .strava,
            credentials: .oauth(accessToken: "a", refreshToken: "r", expiresAt: expiresAt)
        )

        await sut.disconnect(.strava)

        let renewals = await sut.sourcesNeedingRenewal(now: afterExpiry)
        XCTAssertTrue(renewals.isEmpty)
    }

    func testTheRenewalPromptNamesTheSource() {
        XCTAssertEqual(ConnectorSource.strava.renewalPrompt, "Renew your Strava connection")
        XCTAssertEqual(ConnectorSource.hevy.renewalPrompt, "Renew your Hevy connection")
    }
}
