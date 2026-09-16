import Foundation

/// Drives the Strava connection screen (#140, US-5 AC1): runs the OAuth flow
/// with the user's own application credentials, keeps the resulting token pair
/// and the registry in step, and tears the connection down again.
///
/// The screen is the only place a Strava connection *starts*; keeping it
/// alive is the connector's job (refresh, #142), and telling the dashboard it
/// has lapsed is the registry's (US-5 AC2). What this type owns is the
/// hand-over between the three: a pair that came back from the browser is
/// stored first and handed to the registry second, so a crash in between
/// leaves a stored pair the next launch can pick up rather than a connection
/// only the registry remembers.
@MainActor
final class StravaConnectionViewModel: ObservableObject {
    @Published private(set) var state: StravaConnectionState = .unknown

    /// Invoked after a pair was stored and the registry accepted it. The
    /// dashboard has to sync again — its own `.task` does not fire when the
    /// user switches back to it.
    var onConnected: (() -> Void)?
    /// Invoked after a disconnect: the Strava sessions are gone from the
    /// cache, and the dashboard has to stop showing them.
    var onDisconnected: (() -> Void)?

    private let oauth: any StravaOAuthorizing
    private let credentialStore: any StravaCredentialStoring
    private let registry: ConnectorRegistry
    private let sessionReset: any SessionResetting
    private let now: () -> Date

    /// - Parameters:
    ///   - registry: The app's shared registry, with the Strava connector
    ///     already registered — a connection this screen makes has to be the
    ///     one the sync and the dashboard see.
    ///   - sessionReset: Drops the cached Strava sessions on disconnect.
    ///   - now: Injectable clock, so expiry is testable.
    init(
        oauth: any StravaOAuthorizing,
        credentialStore: any StravaCredentialStoring,
        registry: ConnectorRegistry,
        sessionReset: any SessionResetting,
        now: @escaping () -> Date = Date.init
    ) {
        self.oauth = oauth
        self.credentialStore = credentialStore
        self.registry = registry
        self.sessionReset = sessionReset
        self.now = now
    }

    // MARK: - Derived

    /// "Connect" (or "Reconnect") is offered whenever credentials are in
    /// place and no flow is running — a connected source can be reconnected
    /// too, which is how a pair tied to replaced credentials is renewed.
    var canConnect: Bool {
        switch state {
        case .idle, .connected, .expired, .failed: return true
        case .unknown, .missingCredentials, .authorizing: return false
        }
    }

    /// Whether there is (or may be) a stored pair to tear down.
    ///
    /// `.failed(.keychain)` counts: the Keychain refused a write, so what is
    /// stored is unknown — after a disconnect that could not clear it, the
    /// tokens are still there and the user has to be able to try again.
    var isConnected: Bool {
        switch state {
        case .connected, .expired, .failed(.keychain): return true
        case .unknown, .missingCredentials, .idle, .authorizing, .failed: return false
        }
    }

    // MARK: - Lifecycle

    /// Re-reads the stores: on every appearance of the screen, so a pair
    /// entered on the credentials screen a moment ago is reflected too. A
    /// running flow is left alone.
    ///
    /// A stored pair is handed to the registry so the renewal prompt and the
    /// sync see the same connection this screen does. A pair whose access
    /// token has run out is not reported as expired right away: the access
    /// token lives six hours, so every returning user would otherwise read
    /// "could not be renewed" over a connection the next sync renews on its
    /// own (US-5 AC4). The connector is asked to refresh first, and only a
    /// pair Strava rejects — or one that cannot be checked — stays expired.
    func refreshStoredState() async {
        guard state != .authorizing else { return }

        let client: StravaClientCredentials?
        let stored: ConnectorCredentials?
        do {
            client = try await credentialStore.clientCredentials()
            stored = try await credentialStore.credentials()
        } catch {
            // A Keychain that refuses the read (device just unlocked, prewarm
            // launch) is not "nothing entered": reporting it as missing
            // credentials would hide a complete set-up behind a wrong message.
            state = .failed(.keychain)
            return
        }
        guard client != nil else {
            state = .missingCredentials
            return
        }
        guard let stored else {
            state = .idle
            return
        }

        // A connector that refuses the pair (empty token) leaves the source
        // disconnected, and the screen offers to connect afresh. `IfNewer`:
        // a pair the connector has refreshed since is not overwritten.
        try? await registry.connectIfNewer(.strava, credentials: stored)
        var registryState = await registry.state(of: .strava, now: now())
        if case .expired = registryState {
            registryState = await renewedState(after: registryState)
        }
        state = Self.state(from: registryState)
    }

    /// Lets the connector refresh a run-out pair and, when it did, brings the
    /// registry's expiry bookkeeping up to the rotated pair it persisted.
    /// Anything but a successful refresh leaves `expired` in place.
    private func renewedState(after expired: ConnectorConnectionState) async -> ConnectorConnectionState {
        let renewed = (try? await registry.validate(.strava)) ?? false
        guard renewed, let fresh = try? await credentialStore.credentials() else { return expired }
        try? await registry.connectIfNewer(.strava, credentials: fresh)
        return await registry.state(of: .strava, now: now())
    }

    /// Runs the browser flow and, on success, stores the pair and connects the
    /// registry.
    func connect() async {
        guard canConnect else { return }
        let resting = state

        let client: StravaClientCredentials?
        do {
            client = try await credentialStore.clientCredentials()
        } catch {
            state = .failed(.keychain)
            return
        }
        guard let client else {
            state = .missingCredentials
            return
        }

        state = .authorizing
        let pair: ConnectorCredentials
        do {
            pair = try await oauth.authorize(client)
        } catch let error as StravaOAuthError {
            // A dismissed sheet is not a failure: back to where the user was.
            state = StravaConnectionFailure(error).map { .failed($0) } ?? resting
            return
        } catch {
            state = .failed(.network)
            return
        }

        guard case let .oauth(accessToken, refreshToken, expiresAt) = pair else {
            state = .failed(.invalidResponse)
            return
        }

        do {
            try await credentialStore.saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        } catch {
            state = .failed(.keychain)
            return
        }

        do {
            try await registry.connect(.strava, credentials: pair)
        } catch {
            // The registry did not take the pair, so the screen cannot claim
            // a connection — and the stored pair goes again, or the next sync
            // would quietly pull Strava sessions in under a screen that says
            // "not connected". The application credentials stay: they were
            // not what failed.
            try? await credentialStore.clearTokens()
            state = .failed(.invalidResponse)
            return
        }

        state = .connected(expiresAt: expiresAt)
        onConnected?()
    }

    /// Tears the connection down: the registry forgets it, every Strava item
    /// leaves the Keychain — application credentials included — and the
    /// cached Strava sessions go. The Hevy session is not touched.
    ///
    /// Every step runs whatever the others did (the stance of
    /// `SessionResetService`): a Keychain that refuses the delete must not
    /// leave the cached sessions on the dashboard, and the failure is shown
    /// with the Disconnect button still offered, so the user can try again.
    func disconnect() async {
        guard state != .authorizing else { return }

        await registry.disconnect(.strava)
        await sessionReset.discardCachedWorkouts(from: .strava)
        do {
            try await credentialStore.clear()
        } catch {
            state = .failed(.keychain)
            onDisconnected?()
            return
        }
        state = .missingCredentials
        onDisconnected?()
    }

    // MARK: - Mapping

    private static func state(from registryState: ConnectorConnectionState) -> StravaConnectionState {
        switch registryState {
        case .disconnected:
            return .idle
        case .connected(let expiresAt):
            // Strava pairs always carry an expiry; a `nil` here would mean an
            // API-key scheme, which this source does not have.
            return expiresAt.map { .connected(expiresAt: $0) } ?? .idle
        case .expired(let since):
            return .expired(since: since)
        }
    }
}
