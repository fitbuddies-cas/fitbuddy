import Foundation
import OSLog

/// Reads training data from the Hevy API and hands it back normalized
/// (ADR-6, #34).
///
/// The connector is the only type that knows Hevy exists: it owns the wire
/// DTOs, the pagination of `GET /v1/workouts` and the mapping of HTTP status
/// codes onto `ConnectorError`. Everything above it — the sync service, the
/// dashboard, the prompt builder — sees `Activity` and `ConnectorError` only,
/// so a second source (#35) is a new conforming type rather than a refactor of
/// those layers.
///
/// Deliberately *not* part of the connector: the Keychain, the local cache and
/// the sync timestamp. Those belong to the app's session, not to the provider,
/// and `WorkoutSyncService` orchestrates them around this type.
actor HevyConnector: FitnessConnector {
    /// Hevy caps `pageSize` at 10 for the workouts endpoint.
    private static let pageSize = 10
    /// Safety stop for the pagination loop, at 10 workouts per page: 1000
    /// workouts is far more than a 90-day window can hold, so hitting this
    /// means Hevy is paginating in a way this version does not understand.
    private static let maxPages = 100
    private static let workoutsURL = URL(staticString: "https://api.hevyapp.com/v1/workouts")

    private let session: URLSession
    /// The key sent with every request, held only in memory — the Keychain
    /// stays the caller's business (see `disconnect()`).
    private var apiKey: String?

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "HevyConnector")

    /// - Parameter session: Injectable for tests (stub `URLProtocol`);
    ///   defaults to the ephemeral `.fitBuddy` session so the key-bearing
    ///   request is never cached to disk.
    init(session: URLSession = .fitBuddy) {
        self.session = session
    }

    // MARK: - FitnessConnector

    /// Stores the Hevy API key for subsequent calls.
    ///
    /// - Throws: `ConnectorError.unauthorized` for credentials that are not an
    ///   API key at all — an OAuth pair means the caller wired up the wrong
    ///   connector, and failing here is louder than sending a request without
    ///   a key.
    func connect(credentials: ConnectorCredentials) async throws {
        guard case let .apiKey(key) = credentials, !key.isEmpty else {
            throw ConnectorError.unauthorized
        }
        apiKey = key
    }

    /// Confirms the stored key with the smallest authenticated call the API
    /// offers: one page holding one workout.
    ///
    /// Hevy keys do not expire, so this is a plain ping — no refresh, unlike
    /// the OAuth connectors ADR-6 anticipates.
    func validate() async throws -> Bool {
        // Without a key there is nothing to validate; asking Hevy would return
        // a "no" about a key the user never gave us.
        guard apiKey != nil else { throw ConnectorError.unauthorized }
        do {
            _ = try await fetchPage(1, pageSize: 1)
            return true
        } catch ConnectorError.unauthorized {
            // The one case that is an answer rather than a failure: Hevy has
            // said the key is not valid.
            return false
        }
    }

    /// Every workout that started at or after `since`, newest first.
    ///
    /// Pagination is internal (ADR-6): the caller gets one flat list, never a
    /// cursor. The walk stops at the first page that lies entirely outside the
    /// window instead of downloading the user's whole history.
    func fetchActivities(since: Date) async throws -> [Activity] {
        var collected: [Activity] = []
        var seenIDs: Set<String> = []
        var page = 1

        while page <= Self.maxPages {
            let payload = try await fetchPage(page, pageSize: Self.pageSize)
            let inWindow = payload.workouts.filter { $0.startTime >= since }
            // Hevy paginates newest first over a live list: a workout logged
            // while the walk is between two pages shifts everything down a slot
            // and hands the entry on the boundary back twice. A duplicate would
            // be cached — and would inflate every count and volume the
            // dashboard derives.
            collected.append(contentsOf: inWindow.lazy
                .filter { seenIDs.insert($0.id).inserted }
                .map { $0.makeActivity() })

            // A page that contributes nothing ends the walk: it holds either no
            // workouts at all, or none inside the window — and Hevy serves
            // newest first, so there is nothing behind it either way.
            // `page_count` cannot be trusted to say so: it is decoded leniently,
            // so a bogus value would otherwise send up to `maxPages` requests on
            // the user's key that all return nothing, after which the empty
            // result wipes the cache as a "successful" sync.
            if inWindow.isEmpty { break }
            if page >= max(payload.pageCount, 1) { break }
            page += 1
        }

        if page > Self.maxPages {
            logger.error("Pagination stopped at the \(Self.maxPages, privacy: .public)-page cap")
        }
        return collected
    }

    /// Drops the in-memory key. The stored one stays where it is — clearing
    /// the Keychain is the caller's decision (`SessionResetService`).
    func disconnect() async {
        apiKey = nil
    }

    // MARK: - Requests

    private func fetchPage(_ page: Int, pageSize: Int) async throws -> HevyWorkoutsPage {
        guard let apiKey else { throw ConnectorError.unauthorized }

        var request = URLRequest(url: try pageURL(page, pageSize: pageSize))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        // No per-request timeout: `.fitBuddy` sets 15s on the configuration, and
        // a per-request value does not reliably override it. One page is 10
        // workouts, so the session default is ample.

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // A cancelled request (user navigated away, a newer sync superseded
            // this one) is not a connectivity problem and must not surface as
            // one — rethrow it untouched.
            if error.isCancellation { throw error }
            throw ConnectorError.networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.networkUnavailable
        }
        try validate(http)

        do {
            return try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)
        } catch {
            logger.error("Page \(page, privacy: .public) could not be decoded: \(error, privacy: .public)")
            throw ConnectorError.invalidResponse
        }
    }

    private func pageURL(_ page: Int, pageSize: Int) throws -> URL {
        var components = URLComponents(url: Self.workoutsURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ]
        // Unreachable with a static base URL and numeric query items, but the
        // alternative would be a force-unwrap.
        guard let url = components?.url else { throw ConnectorError.invalidResponse }
        return url
    }

    // MARK: - Error mapping

    /// Maps a non-2xx status onto the `ConnectorError` vocabulary every layer
    /// above reads (ADR-6).
    private func validate(_ http: HTTPURLResponse) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw ConnectorError.unauthorized
        case 429:
            throw ConnectorError.rateLimited(retryAfter: Self.retryAfter(from: http))
        case 500...599:
            throw ConnectorError.serviceUnavailable
        default:
            // 403 lands here rather than in the 401 branch: Hevy returns it for
            // valid keys too (WAF, geo), and reporting it as an auth failure
            // would wipe a working key. `ConnectorError` has no case for "odd
            // status", so it is reported as a response this version cannot
            // work with and the code goes to the log.
            logger.error("Unexpected status \(http.statusCode, privacy: .public)")
            throw ConnectorError.invalidResponse
        }
    }

    /// Reads `Retry-After` (seconds form only — Hevy does not send HTTP dates).
    private static func retryAfter(from http: HTTPURLResponse) -> TimeInterval? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(raw.trimmingCharacters(in: .whitespaces))
    }
}
