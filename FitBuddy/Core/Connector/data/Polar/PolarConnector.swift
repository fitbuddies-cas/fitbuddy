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
/// Credential handling follows the same split as `HevyService`: this actor
/// holds the tokens in memory and refreshes an expired access token, but does
/// **not** persist anything. The owning service reads the stored tokens and
/// the `member-id` from the Keychain, passes them in, and writes back whatever
/// `currentCredentials()` returns after a sync.
actor PolarConnector: FitnessConnector {
    /// Refresh the access token this long before it actually expires, so a
    /// sync started right on the boundary does not race the clock.
    private static let refreshLeeway: TimeInterval = 60

    private let oauth: PolarOAuthClient
    private let accessLink: PolarAccessLinkClient
    /// FitBuddy's own stable identifier for this user with AccessLink.
    private let memberID: String
    private let now: () -> Date
    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "PolarConnector")

    private var credentials: ConnectorCredentials?
    /// `true` once the user has been registered with AccessLink in this
    /// process — the call is idempotent server-side, this just skips the
    /// round-trip on every subsequent sync.
    private var didRegister = false

    /// Designated initializer — the OAuth and AccessLink clients are injected
    /// so tests can drive them with a stub `URLSession`.
    init(
        oauth: PolarOAuthClient,
        accessLink: PolarAccessLinkClient,
        memberID: String,
        now: @escaping () -> Date = Date.init
    ) {
        self.oauth = oauth
        self.accessLink = accessLink
        self.memberID = memberID
        self.now = now
    }

    /// Convenience initializer wiring the clients from one configuration.
    init(
        configuration: PolarClientConfiguration,
        memberID: String,
        session: URLSession = .fitBuddy,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            oauth: PolarOAuthClient(configuration: configuration, session: session, now: now),
            accessLink: PolarAccessLinkClient(
                baseURL: configuration.accessLinkBaseURL,
                session: session
            ),
            memberID: memberID,
            now: now
        )
    }

    /// Tokens as they currently stand, including any refresh performed during
    /// the last call — the owning service persists these to the Keychain.
    func currentCredentials() -> ConnectorCredentials? {
        credentials
    }

    // MARK: - FitnessConnector

    func connect(credentials: ConnectorCredentials) async throws {
        guard case .oauth = credentials else {
            // Polar has no long-lived API key; an `.apiKey` credential cannot
            // authenticate here and is a programming error at the call site.
            logger.error("PolarConnector requires OAuth credentials, got .apiKey")
            throw ConnectorError.unauthorized
        }
        self.credentials = credentials
        didRegister = false
    }

    func validate() async throws -> Bool {
        do {
            let token = try await freshAccessToken()
            _ = try await accessLink.exercises(accessToken: token)
            return true
        } catch ConnectorError.unauthorized {
            // Contract: `false` is an explicit rejection, a thrown error is
            // everything that isn't a clear yes/no.
            return false
        }
    }

    func fetchActivities(since: Date) async throws -> [Activity] {
        let token = try await freshAccessToken()

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
        credentials = nil
        didRegister = false
    }

    // MARK: - Token lifecycle

    /// Returns a usable access token, refreshing first if the stored one is
    /// within `refreshLeeway` of expiry. A dead refresh token surfaces as
    /// `ConnectorError.unauthorized` from `PolarOAuthClient`.
    private func freshAccessToken() async throws -> String {
        guard case .oauth(let access, let refresh, let expiresAt) = credentials else {
            throw ConnectorError.unauthorized
        }
        guard expiresAt.timeIntervalSince(now()) <= Self.refreshLeeway else {
            return access
        }
        guard !refresh.isEmpty else {
            // Access token expired and no refresh token to recover with.
            throw ConnectorError.unauthorized
        }

        let refreshed = try await oauth.refresh(refreshToken: refresh)
        credentials = refreshed
        guard case .oauth(let newAccess, _, _) = refreshed else {
            throw ConnectorError.invalidResponse
        }
        return newAccess
    }
}
