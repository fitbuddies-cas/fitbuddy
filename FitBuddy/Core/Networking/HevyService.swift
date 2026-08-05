import Foundation
import OSLog

/// Loads the dashboard's 90-day workout window from Hevy (US-2) and caches it
/// locally.
///
/// `GET /v1/workouts` is capped at 10 workouts per page, so a full window is a
/// handful of requests; the pagination loop is contained here and callers only
/// ever see a completed window (ADR-006). On HTTP 401 the service performs the
/// hard logout demanded by US-1 AC3 before rethrowing.
actor HevyService: WorkoutSyncing {
    /// Hevy caps `pageSize` at 10 for this endpoint.
    private static let pageSize = 10
    /// Dashboard window in days (US-2).
    private static let windowDays = 90
    /// Safety stop for the pagination loop, at 10 workouts per page: 1000
    /// workouts is far more than a 90-day window can hold, so hitting this
    /// means Hevy is paginating in a way this version does not understand.
    private static let maxPages = 100
    private static let workoutsURL = URL(staticString: "https://api.hevyapp.com/v1/workouts")

    private let session: URLSession
    private let keychain: KeychainService
    private let workouts: WorkoutStore
    private let timestamps: SyncTimestampStore
    private let sessionReset: SessionResetService
    private let calendar: Calendar
    private let now: () -> Date

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "HevyService")

    /// - Parameters:
    ///   - session: Injectable for tests (stub `URLProtocol`); defaults to `.shared`.
    ///   - sessionReset: Defaults to one built from the other dependencies —
    ///     it cannot be a default argument because it needs them.
    ///   - now: Injectable clock, so window boundaries are testable.
    init(
        session: URLSession = .shared,
        keychain: KeychainService = KeychainService(),
        workouts: WorkoutStore,
        timestamps: SyncTimestampStore = SyncTimestampStore(),
        sessionReset: SessionResetService? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.keychain = keychain
        self.workouts = workouts
        self.timestamps = timestamps
        self.sessionReset = sessionReset
            ?? SessionResetService(keychain: keychain, workouts: workouts, timestamps: timestamps)
        self.calendar = calendar
        self.now = now
    }

    // MARK: - WorkoutSyncing

    @discardableResult
    func syncRecentWorkouts() async throws -> SyncResult {
        let apiKey = try await storedAPIKey()
        let syncedAt = now()
        let windowStart = windowStart(endingAt: syncedAt)

        let fetched = try await fetchWindow(from: windowStart, apiKey: apiKey)

        do {
            try await workouts.replaceCachedWorkouts(with: fetched)
        } catch {
            // The timestamp stays untouched: nothing new was cached, so the
            // dashboard must keep advertising the older sync (US-2 AC2).
            logger.error("Caching \(fetched.count) workouts failed: \(error, privacy: .public)")
            throw HevyServiceError.persistenceFailed
        }

        await timestamps.setLastSync(syncedAt)
        return SyncResult(workoutCount: fetched.count, syncedAt: syncedAt, windowStart: windowStart)
    }

    // MARK: - Pagination

    /// Walks `GET /v1/workouts` page by page and returns every workout that
    /// started at or after `windowStart`.
    ///
    /// Hevy serves workouts newest first, so the walk stops at the first page
    /// that lies entirely outside the window instead of downloading the user's
    /// whole history. The test is per page rather than per workout on purpose:
    /// a single out-of-order entry at a page boundary then cannot truncate the
    /// window. Hevy does not guarantee this ordering contractually (AR-1) —
    /// worst case the walk ends at `page_count`, which is still correct, only
    /// slower.
    private func fetchWindow(from windowStart: Date, apiKey: String) async throws -> [HevyWorkoutDTO] {
        var collected: [HevyWorkoutDTO] = []
        var page = 1

        while page <= Self.maxPages {
            let payload = try await fetchPage(page, apiKey: apiKey)
            let inWindow = payload.workouts.filter { $0.startTime >= windowStart }
            collected.append(contentsOf: inWindow)

            if inWindow.isEmpty && !payload.workouts.isEmpty { break }
            if page >= max(payload.pageCount, 1) { break }
            page += 1
        }

        if page > Self.maxPages {
            logger.error("Pagination stopped at the \(Self.maxPages, privacy: .public)-page cap")
        }
        return collected
    }

    private func fetchPage(_ page: Int, apiKey: String) async throws -> HevyWorkoutsPage {
        var request = URLRequest(url: try pageURL(page))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HevyServiceError.networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw HevyServiceError.networkUnavailable
        }
        try await validate(http)

        do {
            return try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)
        } catch {
            logger.error("Page \(page, privacy: .public) could not be decoded: \(error, privacy: .public)")
            throw HevyServiceError.invalidResponse
        }
    }

    private func pageURL(_ page: Int) throws -> URL {
        var components = URLComponents(url: Self.workoutsURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(Self.pageSize)),
        ]
        // Unreachable with a static base URL and numeric query items, but the
        // alternative would be a force-unwrap.
        guard let url = components?.url else { throw HevyServiceError.invalidResponse }
        return url
    }

    // MARK: - Error mapping

    /// Maps a non-2xx status to `HevyServiceError`, running the hard logout
    /// before reporting an auth failure.
    private func validate(_ http: HTTPURLResponse) async throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            // US-1 AC3: the stored key was revoked — drop it and the cached
            // data before the caller routes back to onboarding.
            await sessionReset.hardLogout()
            throw HevyServiceError.unauthorized
        case 429:
            throw HevyServiceError.rateLimited(retryAfter: Self.retryAfter(from: http))
        case 500...599:
            throw HevyServiceError.serviceUnavailable
        default:
            // 403 lands here rather than in the 401 branch: Hevy returns it for
            // valid keys too (WAF, geo), and wiping a working key would be the
            // wrong response.
            throw HevyServiceError.unexpectedStatus(http.statusCode)
        }
    }

    /// Reads `Retry-After` (seconds form only — Hevy does not send HTTP dates).
    private static func retryAfter(from http: HTTPURLResponse) -> TimeInterval? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(raw.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Helpers

    private func storedAPIKey() async throws -> String {
        let stored: String?
        do {
            stored = try await keychain.read(.hevyAPIKey)
        } catch {
            logger.error("Keychain read failed: \(error, privacy: .public)")
            throw HevyServiceError.missingAPIKey
        }
        guard let key = stored, !key.isEmpty else { throw HevyServiceError.missingAPIKey }
        return key
    }

    /// Midnight, `windowDays` days before the sync — day-aligned so the window
    /// does not drift with the time of day the user happens to sync.
    private func windowStart(endingAt reference: Date) -> Date {
        let midnight = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .day, value: -Self.windowDays, to: midnight) ?? midnight
    }
}
