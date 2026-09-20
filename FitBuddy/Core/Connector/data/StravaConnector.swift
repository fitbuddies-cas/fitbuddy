import Foundation
import OSLog

/// Reads activities from the Strava API and hands them back normalized
/// (ADR-6, ADR-10, #142). Replaces the #35 stub.
///
/// Built like `HevyConnector`: the only type that knows Strava's wire shape,
/// its pagination and its status codes; everything above sees `Activity` and
/// `ConnectorError`. What it has on top of Hevy is an expiring credential —
/// the access token lives six hours — so `validate()` and `fetchActivities`
/// refresh it through `StravaOAuthorizing` before it runs out (US-5 AC4) and
/// persist the rotated pair through `StravaCredentialStoring`. Strava rotates
/// the refresh token with every refresh, so keeping the new one is not an
/// optimisation but the difference between a connection and a dead one.
///
/// Still not the connector's business: the Keychain items themselves, the
/// cache, the sync timestamp, and what the app does when the user has to
/// re-authorize. `ConnectorRegistry` keeps the expiry bookkeeping for the
/// renewal prompt; this type keeps the token usable for as long as it can.
actor StravaConnector: FitnessConnector {
    /// Strava allows up to 200 per page; 100 keeps a page well under the
    /// session timeout on a slow connection.
    private static let perPage = 100
    /// Safety stop for the pagination loop: 2000 activities is far more than
    /// a 90-day window can hold.
    private static let maxPages = 20
    /// Refresh when less than this remains, so a token cannot expire between
    /// the check and the request that uses it.
    private static let refreshLeeway: TimeInterval = 5 * 60

    private static let activitiesURL = URL(staticString: "https://www.strava.com/api/v3/athlete/activities")
    private static let athleteURL = URL(staticString: "https://www.strava.com/api/v3/athlete")

    private let session: URLSession
    private let oauth: any StravaOAuthorizing
    private let credentialStore: any StravaCredentialStoring
    private let now: () -> Date

    /// The current pair, held only in memory — the Keychain stays the caller's
    /// business, except for the rotated pair a refresh produces.
    private var tokens: Tokens?

    private struct Tokens {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "StravaConnector")

    /// - Parameters:
    ///   - session: Injectable for tests (stub `URLProtocol`); defaults to the
    ///     ephemeral `.fitBuddy` session so a token-bearing request is never
    ///     cached to disk.
    ///   - oauth: Performs the refresh. No default: the real service needs a
    ///     browser seam that belongs to the composition root.
    ///   - credentialStore: Where a rotated pair is persisted, and where the
    ///     client credentials a refresh requires come from.
    ///   - now: Injectable clock, so expiry is testable.
    init(
        session: URLSession = .fitBuddy,
        oauth: any StravaOAuthorizing,
        credentialStore: any StravaCredentialStoring,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.oauth = oauth
        self.credentialStore = credentialStore
        self.now = now
    }

    // MARK: - FitnessConnector

    /// Stores the OAuth pair for subsequent calls.
    ///
    /// - Throws: `ConnectorError.unauthorized` for credentials that are not an
    ///   OAuth pair at all — an API key means the caller wired up the wrong
    ///   connector — or for an empty access token.
    func connect(credentials: ConnectorCredentials) async throws {
        guard case let .oauth(accessToken, refreshToken, expiresAt) = credentials,
              !accessToken.isEmpty
        else { throw ConnectorError.unauthorized }

        tokens = Tokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    /// Confirms the stored pair still works, refreshing it first when it is
    /// about to expire.
    ///
    /// - Returns: `false` when Strava rejected the pair — the refresh token
    ///   was revoked or already rotated, or the client credentials it needs
    ///   are gone — and only the user can renew the connection. `true` after a
    ///   successful refresh or a successful ping.
    /// - Throws: `ConnectorError.unauthorized` when there is no pair to check,
    ///   which after a rejected refresh is the case until the next `connect`.
    func validate() async throws -> Bool {
        guard tokens != nil else { throw ConnectorError.unauthorized }

        if needsRefresh {
            switch await refresh() {
            case .refreshed: return true
            case .rejected: return false
            case .failed(let error): throw error
            case .cancelled: throw CancellationError()
            }
        }

        do {
            _ = try await get(Self.athleteURL)
            return true
        } catch ConnectorError.unauthorized {
            // The one case that is an answer rather than a failure.
            return false
        }
    }

    /// Every activity that started at or after `since`, newest first.
    ///
    /// Pagination is internal (ADR-6). Strava's `after` filter returns the
    /// window oldest first, so the walk cannot stop at "the first page outside
    /// the window" the way Hevy's does; it stops at the first short page
    /// instead, which with a server-side filter is the last one.
    func fetchActivities(since: Date) async throws -> [Activity] {
        let accessToken = try await usableAccessToken()

        var collected: [Activity] = []
        var seenIDs: Set<String> = []
        var page = 1

        while page <= Self.maxPages {
            let entries = try await fetchPage(page, after: since, accessToken: accessToken)
            // `after` is applied server-side, but the cut-off is re-checked so
            // the contract holds whatever the server decides to round.
            let inWindow = entries.filter { $0.startDate >= since }
            // An activity uploaded while the walk is between two pages shifts
            // the boundary entry onto the next page as well; a duplicate would
            // be cached and inflate every count the dashboard derives.
            collected.append(contentsOf: inWindow.lazy
                .filter { seenIDs.insert($0.activityID).inserted }
                .map { $0.makeActivity() })

            if entries.count < Self.perPage { break }
            page += 1
        }

        if page > Self.maxPages {
            logger.error("Pagination stopped at the \(Self.maxPages, privacy: .public)-page cap")
        }
        return collected.sorted { $0.startTime > $1.startTime }
    }

    /// Drops the in-memory pair. The stored one stays where it is — clearing
    /// the Keychain is the caller's decision.
    func disconnect() async {
        tokens = nil
    }

    // MARK: - Token lifecycle

    private var needsRefresh: Bool {
        guard let tokens else { return false }
        return tokens.expiresAt.timeIntervalSince(now()) < Self.refreshLeeway
    }

    private enum RefreshOutcome {
        case refreshed
        /// Strava said no: revoked refresh token, or client credentials gone.
        case rejected
        /// Could not ask — offline, outage.
        case failed(ConnectorError)
        /// The task was cancelled while asking. Not an answer about the pair
        /// and not a connectivity problem: rethrown as a cancellation, the
        /// same rule `get()` follows.
        case cancelled
    }

    /// Exchanges the refresh token for a new pair and persists it.
    ///
    /// The client credentials are read fresh from the store rather than kept
    /// here, so a pair the user replaced on the credentials screen is what the
    /// next refresh uses.
    private func refresh() async -> RefreshOutcome {
        guard let current = tokens else { return .rejected }

        let client: StravaClientCredentials?
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
        } catch let error as StravaOAuthError {
            switch error {
            case .invalidGrant, .invalidClientCredentials:
                // Strava has rotated the pair away (or will not honour it
                // without the right client); keeping it would make every
                // later call in this process re-send a dead refresh token,
                // each one a round-trip against the application's rate limit.
                tokens = nil
                return .rejected
            case .cancelled:
                return .cancelled
            case .transport:
                return .failed(.networkUnavailable)
            case .untrustedConnection:
                return .failed(.untrustedConnection)
            case .unexpectedStatus(let status) where (500...599).contains(status):
                return .failed(.serviceUnavailable)
            case .unexpectedStatus, .invalidResponse, .accessDenied, .stateMismatch, .missingScope, .invalidCallback:
                return .failed(.invalidResponse)
            }
        } catch {
            return error.isCancellation ? .cancelled : .failed(.networkUnavailable)
        }

        guard case let .oauth(accessToken, refreshToken, expiresAt) = renewed else {
            return .failed(.invalidResponse)
        }
        tokens = Tokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)

        // Persist before returning: if the app dies between here and the
        // caller, the old refresh token is already rotated away server-side.
        do {
            try await credentialStore.saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        } catch {
            // The refreshed pair is still usable for this run; the next launch
            // will find the old one and be rejected, which the renewal prompt
            // then handles. Logged, not thrown — the sync can still succeed.
            logger.error("Refreshed Strava tokens not persisted: \(error, privacy: .public)")
        }
        return .refreshed
    }

    /// The access token to send, refreshed first if it is about to expire.
    ///
    /// - Throws: `ConnectorError.unauthorized` when there is no pair or the
    ///   refresh was rejected — the connection has to be renewed by the user.
    private func usableAccessToken() async throws -> String {
        guard tokens != nil else { throw ConnectorError.unauthorized }

        if needsRefresh {
            switch await refresh() {
            case .refreshed: break
            case .rejected: throw ConnectorError.unauthorized
            case .failed(let error): throw error
            case .cancelled: throw CancellationError()
            }
        }
        guard let tokens else { throw ConnectorError.unauthorized }
        return tokens.accessToken
    }

    // MARK: - Requests

    private func fetchPage(_ page: Int, after since: Date, accessToken: String) async throws -> [StravaActivityDTO] {
        var components = URLComponents(url: Self.activitiesURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "after", value: String(Int(since.timeIntervalSince1970))),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(Self.perPage)),
        ]
        // Unreachable with a static base URL and numeric query items, but the
        // alternative would be a force-unwrap.
        guard let url = components?.url else { throw ConnectorError.invalidResponse }

        let data = try await get(url, accessToken: accessToken)
        do {
            return try JSONDecoder.strava.decode([StravaActivityDTO].self, from: data)
        } catch {
            logger.error("Page \(page, privacy: .public) could not be decoded: \(error, privacy: .public)")
            throw ConnectorError.invalidResponse
        }
    }

    /// One authenticated GET, status already checked.
    private func get(_ url: URL, accessToken: String? = nil) async throws -> Data {
        guard let token = accessToken ?? tokens?.accessToken else { throw ConnectorError.unauthorized }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // A cancelled request is not a connectivity problem and must not
            // surface as one — rethrow it untouched.
            if error.isCancellation { throw error }
            if error.isUntrustedConnection { throw ConnectorError.untrustedConnection }
            throw ConnectorError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else { throw ConnectorError.networkUnavailable }
        try validate(http)
        return data
    }

    // MARK: - Error mapping

    /// Maps a non-2xx status onto the `ConnectorError` vocabulary every layer
    /// above reads (ADR-6). Same table as `HevyConnector`, and for the same
    /// reasons.
    private func validate(_ http: HTTPURLResponse) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw ConnectorError.unauthorized
        case 429:
            // Strava signals its 15-minute and daily windows through
            // `X-RateLimit-Usage`, not `Retry-After`; there is no delay to
            // report, only that the caller should back off.
            throw ConnectorError.rateLimited(retryAfter: nil)
        case 500...599:
            throw ConnectorError.serviceUnavailable
        default:
            // 403 lands here rather than in the 401 branch: Strava returns it
            // for a token that lacks a scope as well as for a blocked request,
            // and reporting it as an auth failure would make the user
            // re-authorize a connection that works.
            logger.error("Unexpected status \(http.statusCode, privacy: .public)")
            throw ConnectorError.invalidResponse
        }
    }
}
