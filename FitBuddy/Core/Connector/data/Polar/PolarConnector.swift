import Foundation
import OSLog

/// `FitnessConnector` for Polar endurance data (ADR-11): the third source after
/// Hevy (#34) and ahead of any Strava work (#35).
///
/// Maps Polar AccessLink `GET /v3/exercises` onto the normalized `Activity`
/// model, so the dashboard and AI analysis read a Polar run exactly the way
/// they read a Hevy session — the endurance-only numbers (heart rate,
/// calories, training load) arrive in `Activity.metrics`.
///
/// Built like `StravaConnector` (ADR-11 Nachtrag, BYO-app): an expiring
/// credential — the access token lives ~12h — so `validate()` and
/// `fetchActivities` refresh it through `PolarOAuthorizing` before it runs out
/// (US-5 AC4) and persist the rotated pair through `PolarCredentialStoring`.
/// The user's own application credentials (clientID/secret) are read fresh
/// from the store on every refresh, so a pair the user replaced on the
/// credentials screen is what the next refresh uses.
actor PolarConnector: FitnessConnector {
    /// Refresh the access token this long before it actually expires, so a
    /// sync started right on the boundary does not race the clock.
    private static let refreshLeeway: TimeInterval = 60

    private let accessLink: PolarAccessLinkClient
    private let oauth: any PolarOAuthorizing
    private let credentialStore: any PolarCredentialStoring
    /// FitBuddy's own stable identifier for this user with AccessLink.
    private let memberID: String
    private let now: () -> Date
    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "PolarConnector")

    private var tokens: Tokens?
    /// `true` once the user has been registered with AccessLink in this
    /// process — the call is idempotent server-side, this just skips the
    /// round-trip on every subsequent sync.
    private var didRegister = false

    private struct Tokens {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    /// - Parameters:
    ///   - accessLink: The REST client. Defaults to the fixed AccessLink base
    ///     URL — it needs no per-user configuration.
    ///   - oauth: Performs the refresh. No default: the real service needs a
    ///     browser seam that belongs to the composition root.
    ///   - credentialStore: Where a rotated pair is persisted, and where the
    ///     client credentials a refresh requires come from.
    ///   - memberID: FitBuddy's own stable AccessLink member id for this user.
    ///   - now: Injectable clock, so expiry is testable.
    init(
        accessLink: PolarAccessLinkClient = PolarAccessLinkClient(baseURL: PolarClientConfiguration.accessLinkBaseURL),
        oauth: any PolarOAuthorizing,
        credentialStore: any PolarCredentialStoring,
        memberID: String,
        now: @escaping () -> Date = Date.init
    ) {
        self.accessLink = accessLink
        self.oauth = oauth
        self.credentialStore = credentialStore
        self.memberID = memberID
        self.now = now
    }

    /// Tokens as they currently stand, including any refresh performed during
    /// the last call.
    func currentCredentials() -> ConnectorCredentials? {
        tokens.map { .oauth(accessToken: $0.accessToken, refreshToken: $0.refreshToken, expiresAt: $0.expiresAt) }
    }

    // MARK: - FitnessConnector

    func connect(credentials: ConnectorCredentials) async throws {
        guard case let .oauth(accessToken, refreshToken, expiresAt) = credentials,
              !accessToken.isEmpty
        else {
            // Polar has no long-lived API key; an `.apiKey` credential cannot
            // authenticate here and is a programming error at the call site.
            logger.error("PolarConnector requires OAuth credentials")
            throw ConnectorError.unauthorized
        }
        tokens = Tokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        didRegister = false
    }

    func validate() async throws -> Bool {
        guard tokens != nil else { throw ConnectorError.unauthorized }

        if needsRefresh {
            switch await refresh() {
            case .refreshed: return true
            case .rejected: return false
            case .failed(let error): throw error
            }
        }

        do {
            _ = try await accessLink.exercises(accessToken: tokens!.accessToken)
            return true
        } catch ConnectorError.unauthorized {
            // Contract: `false` is an explicit rejection, a thrown error is
            // everything that isn't a clear yes/no.
            return false
        }
    }

    func fetchActivities(since: Date) async throws -> [Activity] {
        let token = try await usableAccessToken()

        if !didRegister {
            try await accessLink.registerUser(memberID: memberID, accessToken: token)
            didRegister = true
        }

        let exercises = try await accessLink.exercises(accessToken: token)
        let activities = exercises
            .compactMap { $0.makeActivity() }
            .filter { $0.startTime >= since }
            .sorted { $0.startTime > $1.startTime }

        if activities.count != exercises.count {
            logger.info(
                "Polar: \(exercises.count) exercises, \(activities.count) in window since \(since, privacy: .public)"
            )
        }
        return activities
    }

    func disconnect() async {
        tokens = nil
        didRegister = false
    }

    // MARK: - Token lifecycle

    private var needsRefresh: Bool {
        guard let tokens else { return false }
        return tokens.expiresAt.timeIntervalSince(now()) < Self.refreshLeeway
    }

    private enum RefreshOutcome {
        case refreshed
        /// Polar said no: revoked refresh token, or client credentials gone.
        case rejected
        /// Could not ask — offline, outage.
        case failed(ConnectorError)
    }

    /// Exchanges the refresh token for a new pair and persists it.
    ///
    /// The client credentials are read fresh from the store rather than kept
    /// here, so a pair the user replaced on the credentials screen is what the
    /// next refresh uses.
    private func refresh() async -> RefreshOutcome {
        guard let current = tokens else { return .rejected }

        let client: PolarClientCredentials?
        do {
            client = try await credentialStore.clientCredentials()
        } catch {
            logger.error("Client credentials unreadable before refresh: \(error, privacy: .public)")
            return .failed(.unauthorized)
        }
        guard let client else {
            // Without client credentials there is no refresh grant to send.
            return .rejected
        }

        let renewed: ConnectorCredentials
        do {
            renewed = try await oauth.refresh(client, refreshToken: current.refreshToken)
        } catch let error as ConnectorError {
            switch error {
            case .unauthorized: return .rejected
            case .networkUnavailable, .rateLimited, .serviceUnavailable, .invalidResponse, .notImplemented:
                return .failed(error)
            }
        } catch {
            return .failed(.networkUnavailable)
        }

        guard case let .oauth(accessToken, refreshToken, expiresAt) = renewed else {
            return .failed(.invalidResponse)
        }
        tokens = Tokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)

        // Persist before returning: if the app dies between here and the
        // caller, the old refresh token may already be rotated away
        // server-side.
        do {
            try await credentialStore.saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        } catch {
            // The refreshed pair is still usable for this run; the next launch
            // will find the old one and be rejected, which the renewal prompt
            // then handles. Logged, not thrown — the sync can still succeed.
            logger.error("Refreshed Polar tokens not persisted: \(error, privacy: .public)")
        }
        return .refreshed
    }

    /// The access token to send, refreshed first if it is about to expire.
    private func usableAccessToken() async throws -> String {
        guard tokens != nil else { throw ConnectorError.unauthorized }

        if needsRefresh {
            switch await refresh() {
            case .refreshed: break
            case .rejected: throw ConnectorError.unauthorized
            case .failed(let error): throw error
            }
        }
        guard let tokens else { throw ConnectorError.unauthorized }
        return tokens.accessToken
    }
}
