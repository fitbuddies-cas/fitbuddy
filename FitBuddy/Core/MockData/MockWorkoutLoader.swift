import Foundation

// Development fixture: excluded from Release builds, so no mock training
// history can reach a TestFlight binary. The payloads themselves are
// stripped from the Release bundle via EXCLUDED_SOURCE_FILE_NAMES.
#if DEBUG

/// Reads the bundled mock payloads (#44, #188) and hands them out either as
/// cache models or as `GET /v1/workouts` pages.
///
/// A payload file holds nothing but the sessions of one source, in that
/// source's own wire format: Hevy's `{"workouts": [...]}`, and the bare arrays
/// Strava's `GET /athlete/activities` and Polar's `GET /v3/exercises` return.
/// A Hevy file may carry a `routines` array beside its workouts — the entries
/// of `GET /v1/routines` its workouts name by `routine_id` — so a profile can
/// have rep targets (#240, #233); the join is the connector's own.
/// Each is decoded through that source's own DTO — `HevyWorkoutDTO`,
/// `StravaActivityDTO`, `PolarExerciseDTO` — so anything built against them
/// (SwiftUI previews, dashboard metrics, an analysis run, a stubbed
/// `URLProtocol`) sees exactly what the API delivers, and a cardio profile
/// gets its `ActivityKind` and `CardioMetrics` from the real mapping rather
/// than from a fixture's opinion. The wire types are the one place outside the
/// connectors that names a provider, and deliberately so: these are recorded
/// payloads, and a fixture that decoded them through anything else would stop
/// proving what it exists to prove. The files are DEBUG-only and never ship
/// (#44). Hevy's `page`/`page_count` envelope is not stored, it is built per
/// request in `pageData(for:page:pageSize:)`, so a file can never claim a page
/// count that contradicts the request it answers.
///
/// **Re-anchoring:** the payloads carry fixed timestamps, which would age out
/// of the dashboard's 90-day window (US-2) within weeks. The loader therefore
/// shifts every timestamp by whole days, so the newest session lands inside the
/// last 24 hours before `now` and the remaining sessions keep their spacing and
/// time of day. The shift is computed **once per profile, over all its payloads
/// together**: a mixed profile whose Hevy and Strava halves were anchored
/// separately would move its lifts and its runs against each other and lose
/// exactly the overlap days it exists to show. Whole days and one offset is
/// also what lets a profile keep its day counts in every time zone — see the
/// note on `MockWorkoutProfile` for the other half of that, which is a property
/// of the payloads rather than of this loader.
///
/// ```swift
/// // Preview / debug seeding:
/// let workouts = (try? MockWorkoutLoader().workouts(for: .personA)) ?? []
///
/// // Stubbing the Hevy network path, page by page:
/// let payload = try MockWorkoutLoader().pageData(for: .personB, page: 1)
/// ```
struct MockWorkoutLoader {
    /// Hevy caps `pageSize` at 10; mirrored so mock pages paginate like the API.
    static let pageSize = 10

    /// Workout-level timestamps in Hevy's payload. Exercises and sets carry none.
    private static let hevyTimestampKeys = ["start_time", "end_time", "updated_at", "created_at"]

    private let bundle: Bundle

    /// Read once at init, not per call: every page of one walk is anchored to
    /// the same instant, so a walk running across midnight cannot shift its
    /// pages a day against each other.
    private let anchor: Date

    private let cache = Cache()

    /// - Parameters:
    ///   - bundle: Resolved from a type of the app target, so the payloads are
    ///     found from previews and from the (app-hosted) test bundle alike.
    ///   - now: Injectable clock, so re-anchoring is testable. Called exactly
    ///     once, when the loader is created.
    init(bundle: Bundle = Bundle(for: Workout.self), now: () -> Date = Date.init) {
        self.bundle = bundle
        self.anchor = now()
    }

    // MARK: - Workouts

    /// Every session of `profile`, from every source, newest first, as cache
    /// models ready to be inserted into a `ModelContext` or handed to a view.
    func workouts(for profile: MockWorkoutProfile) throws -> [Workout] {
        try activities(for: profile).map { $0.makeWorkout() }
    }

    /// Every session of `profile` as the normalized `Activity` a connector
    /// would hand back — what the cache is written from (#148), newest first
    /// across all sources.
    func activities(for profile: MockWorkoutProfile) throws -> [Activity] {
        try profile.payloads
            .flatMap { try activities(for: profile, from: $0.source) }
            .sorted { $0.startTime > $1.startTime }
    }

    /// The sessions one source contributes to `profile`, newest first — what
    /// `WorkoutStore.replaceCachedWorkouts(from:with:)` takes, one source at a
    /// time (#188).
    ///
    /// Throws `.noPayload` for a source this profile records nothing from: a
    /// caller asking for the runner's lifts has made a mistake, and an empty
    /// array would answer it with "trained nothing" instead.
    func activities(
        for profile: MockWorkoutProfile,
        from source: ConnectorSource
    ) throws -> [Activity] {
        guard let payload = profile.payloads.first(where: { $0.source == source }) else {
            throw MockWorkoutError.noPayload(profile: profile.rawValue, source: source)
        }
        let entries = try shiftedEntries(for: profile, payload: payload)
        let data = try serialized(entries, for: payload)
        switch source {
        case .hevy:
            let routines = try routines(of: payload)
            return try decodeHevy(data, name: payload.resourceName).workouts.map { workout in
                workout.makeActivity(routine: workout.routineID.flatMap { routines[$0] })
            }
        case .strava:
            guard let activities = try? JSONDecoder.strava.decode([StravaActivityDTO].self, from: data)
            else { throw MockWorkoutError.invalidPayload(payload.resourceName) }
            return activities.map { $0.makeActivity() }
        case .polar:
            guard let exercises = try? JSONDecoder().decode([PolarExerciseDTO].self, from: data)
            else { throw MockWorkoutError.invalidPayload(payload.resourceName) }
            // A session Polar dated unparseably is dropped by the DTO itself;
            // a fixture that lost one that way is a broken fixture, and the
            // count assertions in `MockWorkoutLoaderTests` are what catch it.
            return exercises.compactMap { $0.makeActivity() }
        }
    }

    /// The profile's whole Hevy history as a single decoded page.
    func page(for profile: MockWorkoutProfile) throws -> HevyWorkoutsPage {
        let data = try pageData(for: profile, page: 1, pageSize: Int.max)
        return try decodeHevy(data, name: try hevyPayload(of: profile).resourceName)
    }

    // MARK: - Wire format

    /// One `GET /v1/workouts?page=<page>&pageSize=<pageSize>` payload, ready to
    /// be returned from a stubbed `URLProtocol`.
    ///
    /// `page` is clamped into the available range, mirroring Hevy, which serves
    /// the last page rather than an error for an overshooting page number.
    /// Hevy-only by nature: this is Hevy's envelope, and a profile without a
    /// Hevy payload has no page to serve.
    func pageData(
        for profile: MockWorkoutProfile,
        page: Int = 1,
        pageSize: Int = pageSize
    ) throws -> Data {
        let payload = try hevyPayload(of: profile)
        let workouts = try shiftedEntries(for: profile, payload: payload)
        let size = max(1, pageSize)
        let pageCount = max(1, Int((Double(workouts.count) / Double(size)).rounded(.up)))
        let clamped = min(max(page, 1), pageCount)
        let slice = Array(workouts.dropFirst((clamped - 1) * size).prefix(size))

        let body: [String: Any] = [
            "page": clamped,
            "page_count": pageCount,
            "workouts": slice,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw MockWorkoutError.invalidPayload(payload.resourceName)
        }
        return data
    }

    private func hevyPayload(of profile: MockWorkoutProfile) throws -> MockWorkoutPayload {
        guard let payload = profile.hevyPayload else {
            throw MockWorkoutError.noPayload(profile: profile.rawValue, source: .hevy)
        }
        return payload
    }

    private func decodeHevy(_ data: Data, name: String) throws -> HevyWorkoutsPage {
        guard let page = try? JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data) else {
            throw MockWorkoutError.invalidPayload(name)
        }
        return page
    }

    /// The entries of one payload, back in the shape its DTO decodes: Hevy's
    /// envelope, or the bare array the other two return.
    private func serialized(_ entries: [[String: Any]], for payload: MockWorkoutPayload) throws -> Data {
        let body: Any = payload.source == .hevy ? ["workouts": entries] : entries
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw MockWorkoutError.invalidPayload(payload.resourceName)
        }
        return data
    }

    // MARK: - Loading & re-anchoring

    /// One payload's sessions with all timestamps moved into the present.
    ///
    /// Cached per loader and per payload: walking a profile page by page would
    /// otherwise re-read and re-parse the whole payload once per page.
    private func shiftedEntries(
        for profile: MockWorkoutProfile,
        payload: MockWorkoutPayload
    ) throws -> [[String: Any]] {
        if let cached = cache.shifted[payload] { return cached }
        let offset = try self.offset(for: profile)
        let entries = try rawEntries(of: payload)
        let shifted = offset == 0 ? entries : entries.map { shift($0, by: offset, from: payload.source) }
        cache.shifted[payload] = shifted
        return shifted
    }

    /// How far the whole profile moves — whole days, rounded down, so its
    /// newest session ends up at most 24 hours old and never in the future.
    ///
    /// Over every payload at once. A profile's sources describe one person's
    /// week, and a per-file offset would slide the runs off the days that
    /// carried the lifts.
    private func offset(for profile: MockWorkoutProfile) throws -> TimeInterval {
        if let cached = cache.offsets[profile] { return cached }
        var newest: Date?
        for payload in profile.payloads {
            let starts = try rawEntries(of: payload).compactMap { start(of: $0, from: payload.source) }
            if let latest = starts.max(), latest > (newest ?? .distantPast) { newest = latest }
        }
        guard let newest else { return 0 }
        let days = (anchor.timeIntervalSince(newest) / 86_400).rounded(.down)
        let offset = days * 86_400
        cache.offsets[profile] = offset
        return offset
    }

    /// The routines a Hevy fixture carries next to its workouts, keyed by id
    /// — in the shape `GET /v1/routines` returns them, decoded through the
    /// real DTO like everything else here (#233).
    ///
    /// Optional: a fixture without a `routines` key is a user who logs
    /// freely, and its sessions carry no rep targets. The routine's
    /// `updated_at` is not re-anchored; it is a snapshot date the analysis
    /// never compares against the window.
    private func routines(of payload: MockWorkoutPayload) throws -> [String: HevyRoutineDTO] {
        guard payload.source == .hevy else { return [:] }
        if let cached = cache.routines[payload] { return cached }
        let root = try rawRoot(of: payload)
        var routines: [String: HevyRoutineDTO] = [:]
        if let raw = root["routines"] {
            guard let entries = raw as? [[String: Any]],
                  let data = try? JSONSerialization.data(withJSONObject: entries),
                  let decoded = try? JSONDecoder.hevy.decode([HevyRoutineDTO].self, from: data)
            else { throw MockWorkoutError.invalidPayload(payload.resourceName) }
            for routine in decoded { routines[routine.id] = routine }
        }
        cache.routines[payload] = routines
        return routines
    }

    /// A Hevy fixture's root object — read once per payload for the workouts
    /// and the routines alike.
    private func rawRoot(of payload: MockWorkoutPayload) throws -> [String: Any] {
        guard let root = try rawJSON(of: payload) as? [String: Any] else {
            throw MockWorkoutError.invalidPayload(payload.resourceName)
        }
        return root
    }

    /// A Strava or Polar fixture's root array.
    private func rawArray(of payload: MockWorkoutPayload) throws -> [[String: Any]] {
        guard let array = try rawJSON(of: payload) as? [[String: Any]] else {
            throw MockWorkoutError.invalidPayload(payload.resourceName)
        }
        return array
    }

    /// The parsed file, cached per payload so the two readers of a Hevy file
    /// share one read.
    private func rawJSON(of payload: MockWorkoutPayload) throws -> Any {
        if let cached = cache.json[payload] { return cached }
        guard let url = bundle.url(forResource: payload.resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw MockWorkoutError.missingPayload(payload.resourceName)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw MockWorkoutError.invalidPayload(payload.resourceName)
        }
        cache.json[payload] = root
        return root
    }

    private func rawEntries(of payload: MockWorkoutPayload) throws -> [[String: Any]] {
        if let cached = cache.raw[payload] { return cached }
        let entries: [[String: Any]]?
        switch payload.source {
        case .hevy: entries = try rawRoot(of: payload)["workouts"] as? [[String: Any]]
        case .strava, .polar: entries = try rawArray(of: payload)
        }
        guard let entries else { throw MockWorkoutError.invalidPayload(payload.resourceName) }
        cache.raw[payload] = entries
        return entries
    }

    /// When one session started, read in its source's own wire format.
    private func start(of entry: [String: Any], from source: ConnectorSource) -> Date? {
        switch source {
        case .hevy:
            return (entry["start_time"] as? String).flatMap(Self.isoDate(from:))
        case .strava:
            return (entry["start_date"] as? String).flatMap(Self.isoDate(from:))
        case .polar:
            guard let raw = entry["start_time"] as? String,
                  let local = PolarDate.localFormatter.date(from: raw) else { return nil }
            let minutes = entry["start_time_utc_offset"] as? Int ?? 0
            return local.addingTimeInterval(TimeInterval(-minutes * 60))
        }
    }

    private func shift(
        _ entry: [String: Any],
        by offset: TimeInterval,
        from source: ConnectorSource
    ) -> [String: Any] {
        var shifted = entry
        switch source {
        case .hevy:
            for key in Self.hevyTimestampKeys {
                guard let raw = entry[key] as? String, let date = Self.isoDate(from: raw) else { continue }
                shifted[key] = ISO8601DateFormatter.hevyPlain.string(from: date.addingTimeInterval(offset))
            }
        case .strava:
            if let raw = entry["start_date"] as? String, let date = Self.isoDate(from: raw) {
                shifted["start_date"] = ISO8601DateFormatter.hevyPlain.string(
                    from: date.addingTimeInterval(offset)
                )
            }
        case .polar:
            // Polar's `start_time` is a local wall clock with the zone carried
            // beside it. The offset is whole days, so the wall clock moves by
            // the same whole days and `start_time_utc_offset` stays what it
            // was — the session keeps the local time of day it was recorded at.
            if let raw = entry["start_time"] as? String,
               let local = PolarDate.localFormatter.date(from: raw) {
                shifted["start_time"] = PolarDate.localFormatter.string(
                    from: local.addingTimeInterval(offset)
                )
            }
        }
        return shifted
    }

    private static func isoDate(from raw: String) -> Date? {
        ISO8601DateFormatter.hevyPlain.date(from: raw)
            ?? ISO8601DateFormatter.hevyFractional.date(from: raw)
    }

    /// Shared storage for the copies of one loader — the loader stays a value
    /// type, the parsed payloads are computed once.
    private final class Cache {
        var json: [MockWorkoutPayload: Any] = [:]
        var raw: [MockWorkoutPayload: [[String: Any]]] = [:]
        var shifted: [MockWorkoutPayload: [[String: Any]]] = [:]
        var offsets: [MockWorkoutProfile: TimeInterval] = [:]
        var routines: [MockWorkoutPayload: [String: HevyRoutineDTO]] = [:]
    }
}

#endif
