import Foundation

/// Drives the Polar connection screen (#157, US-5 AC1): runs the OAuth flow
/// with the user's own application credentials, keeps the resulting token pair
/// and the registry in step, and tears the connection down again.
///
/// Mirrors `StravaConnectionViewModel` (ADR-11 Nachtrag, BYO-app): a pair that
/// came back from the browser is stored first and handed to the registry
/// second, so a crash in between leaves a stored pair the next launch can
/// pick up rather than a connection only the registry remembers.
@MainActor
final class PolarConnectionViewModel: ObservableObject {
    @Published private(set) var state: PolarConnectionState = .unknown

    /// Invoked after a pair was stored and the registry accepted it. The
    /// dashboard has to sync again — its own `.task` does not fire when the
    /// user switches back to it.
    var onConnected: (() -> Void)?
    /// Invoked after a disconnect: the Polar sessions are gone from the
    /// cache, and the dashboard has to stop showing them.
    var onDisconnected: (() -> Void)?

    private let oauth: any PolarOAuthorizing
    private let credentialStore: any PolarCredentialStoring
    private let registry: ConnectorRegistry
    private let sessionReset: any SessionResetting
    private let now: () -> Date

    /// - Parameters:
    ///   - registry: The app's shared registry, with the Polar connector
    ///     already registered — a connection this screen makes has to be the
    ///     one the sync and the dashboard see.
    ///   - sessionReset: Drops the cached Polar sessions on disconnect.
    ///   - now: Injectable clock, so expiry is testable.
    init(
        oauth: any PolarOAuthorizing,
        credentialStore: any PolarCredentialStoring,
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

    /// Whether there is a stored pair to tear down.
    var isConnected: Bool {
        switch state {
        case .connected, .expired: return true
        case .unknown, .missingCredentials, .idle, .authorizing, .failed: return false
        }
    }

    // MARK: - Lifecycle

    /// Resolves `.unknown` from what is stored: no credentials, credentials
    /// without a pair, or a pair the registry is handed so its expiry
    /// bookkeeping starts.
    func bootstrap() async {
        guard state == .unknown else { return }
        await refreshStoredState()
    }

    /// Re-reads the stores, e.g. after the user came back from the
    /// credentials screen. A running flow is left alone.
    func refreshStoredState() async {
        guard state != .authorizing else { return }

        let client = try? await credentialStore.clientCredentials()
        guard client != nil else {
            state = .missingCredentials
            return
        }

        guard let stored = try? await credentialStore.credentials() else {
            state = .idle
            return
        }

        // A pair the previous launch stored: hand it to the registry so the
        // renewal prompt and the sync see the same connection this screen
        // does. A connector that refuses it (empty token) leaves the source
        // disconnected, and the screen offers to connect afresh.
        try? await registry.connect(.polar, credentials: stored)
        state = Self.state(from: await registry.state(of: .polar, now: now()))
    }

    /// Runs the browser flow and, on success, stores the pair and connects the
    /// registry.
    func connect() async {
        guard canConnect else { return }
        let resting = state

        guard let client = try? await credentialStore.clientCredentials() else {
            state = .missingCredentials
            return
        }

        state = .authorizing
        let pair: ConnectorCredentials
        do {
            pair = try await oauth.authorize(client)
        } catch let error as PolarOAuthError {
            // A dismissed sheet is not a failure: back to where the user was.
            state = PolarConnectionFailure(error).map { .failed($0) } ?? resting
            return
        } catch let error as ConnectorError {
            state = .failed(PolarConnectionFailure(error))
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
            try await registry.connect(.polar, credentials: pair)
        } catch {
            // The pair is stored, so the next launch will retry the hand-over;
            // for now the screen cannot claim a connection the registry does
            // not have.
            state = .failed(.invalidResponse)
            return
        }

        state = .connected(expiresAt: expiresAt)
        onConnected?()
    }

    /// Tears the connection down: the registry forgets it, every Polar item
    /// leaves the Keychain — application credentials included — and the
    /// cached Polar sessions go. The other sources are not touched.
    func disconnect() async {
        guard state != .authorizing else { return }

        await registry.disconnect(.polar)
        do {
            try await credentialStore.clear()
        } catch {
            state = .failed(.keychain)
            return
        }
        await sessionReset.discardCachedWorkouts(from: .polar)
        state = .missingCredentials
        onDisconnected?()
    }

    /// Clears the banner without changing what is stored.
    func dismissFailure() {
        guard case .failed = state else { return }
        Task { await refreshStoredState() }
    }

    // MARK: - Mapping

    private static func state(from registryState: ConnectorConnectionState) -> PolarConnectionState {
        switch registryState {
        case .disconnected:
            return .idle
        case .connected(let expiresAt):
            // Polar pairs always carry an expiry; a `nil` here would mean an
            // API-key scheme, which this source does not have.
            return expiresAt.map { .connected(expiresAt: $0) } ?? .idle
        case .expired(let since):
            return .expired(since: since)
        }
    }
}
