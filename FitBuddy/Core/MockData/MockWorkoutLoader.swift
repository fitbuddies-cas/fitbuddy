import Foundation

// Development fixture: excluded from Release builds, so no mock training
// history can reach a TestFlight binary. The payloads themselves are
// stripped from the Release bundle via EXCLUDED_SOURCE_FILE_NAMES.
#if DEBUG

/// Reads the bundled Hevy mock payloads (#44) and hands them out either as
/// cache models or as `GET /v1/workouts` pages.
///
/// The payload files hold nothing but a `workouts` array in Hevy's wire
/// format; they are decoded through the same `HevyWorkoutDTO` path as live
/// data, so anything built against them — SwiftUI previews, dashboard metrics
/// (#26), a stubbed `URLProtocol` — sees exactly what the API delivers. The
/// wire types are the one place outside `HevyConnector` that names Hevy, and
/// deliberately so: these are recorded Hevy payloads, and a fixture that
/// decoded them through anything else would stop proving what it exists to
/// prove. The file is DEBUG-only and never ships (#44). The
/// `page`/`page_count` envelope is not stored, it is built per request in
/// `pageData(for:page:pageSize:)`, so a file can never claim a page count that
/// contradicts the request it answers.
///
/// **Re-anchoring:** the payloads carry fixed timestamps, which would age out
/// of the dashboard's 90-day window (US-2) within weeks. The loader therefore
/// shifts every timestamp by whole days, so the newest workout lands inside the
/// last 24 hours before `now` and the remaining sessions keep their spacing and
/// time of day.
///
/// ```swift
/// // Preview / debug seeding:
/// let workouts = (try? MockWorkoutLoader().workouts(for: .personA)) ?? []
///
/// // Stubbing the network path, page by page:
/// let payload = try MockWorkoutLoader().pageData(for: .personB, page: 1)
/// ```
struct MockWorkoutLoader {
    /// Hevy caps `pageSize` at 10; mirrored so mock pages paginate like the API.
    static let pageSize = 10

    /// Workout-level timestamps in Hevy's payload. Exercises and sets carry none.
    private static let timestampKeys = ["start_time", "end_time", "updated_at", "created_at"]

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

    /// Every workout of `profile`, newest first, as cache models ready to be
    /// inserted into a `ModelContext` or handed to a view.
    func workouts(for profile: MockWorkoutProfile) throws -> [Workout] {
        try page(for: profile).workouts.map { $0.makeActivity().makeWorkout() }
    }

    /// The profile's whole history as a single decoded page.
    func page(for profile: MockWorkoutProfile) throws -> HevyWorkoutsPage {
        let data = try pageData(for: profile, page: 1, pageSize: Int.max)
        do {
            return try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)
        } catch {
            throw MockWorkoutError.invalidPayload(profile.resourceName)
        }
    }

    // MARK: - Wire format

    /// One `GET /v1/workouts?page=<page>&pageSize=<pageSize>` payload, ready to
    /// be returned from a stubbed `URLProtocol`.
    ///
    /// `page` is clamped into the available range, mirroring Hevy, which serves
    /// the last page rather than an error for an overshooting page number.
    func pageData(
        for profile: MockWorkoutProfile,
        page: Int = 1,
        pageSize: Int = pageSize
    ) throws -> Data {
        let workouts = try shiftedWorkouts(for: profile)
        let size = max(1, pageSize)
        let pageCount = max(1, Int((Double(workouts.count) / Double(size)).rounded(.up)))
        let clamped = min(max(page, 1), pageCount)
        let slice = Array(workouts.dropFirst((clamped - 1) * size).prefix(size))

        let payload: [String: Any] = [
            "page": clamped,
            "page_count": pageCount,
            "workouts": slice,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            throw MockWorkoutError.invalidPayload(profile.resourceName)
        }
        return data
    }

    // MARK: - Loading & re-anchoring

    /// The payload's workouts with all timestamps moved into the present.
    ///
    /// Cached per loader: walking a profile page by page would otherwise re-read
    /// and re-parse the whole payload once per page.
    private func shiftedWorkouts(for profile: MockWorkoutProfile) throws -> [[String: Any]] {
        if let cached = cache.shifted[profile] { return cached }
        let shifted = try makeShiftedWorkouts(for: profile)
        cache.shifted[profile] = shifted
        return shifted
    }

    private func makeShiftedWorkouts(for profile: MockWorkoutProfile) throws -> [[String: Any]] {
        let workouts = try rawWorkouts(for: profile)
        let starts = workouts
            .compactMap { $0["start_time"] as? String }
            .compactMap(Self.date(from:))
        guard let newest = starts.max() else { return workouts }

        // Whole days only, rounded down: the newest workout ends up at most 24
        // hours old and never in the future.
        let days = (anchor.timeIntervalSince(newest) / 86_400).rounded(.down)
        guard days != 0 else { return workouts }
        let offset = days * 86_400
        return workouts.map { shift($0, by: offset) }
    }

    private func rawWorkouts(for profile: MockWorkoutProfile) throws -> [[String: Any]] {
        guard let url = bundle.url(forResource: profile.resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw MockWorkoutError.missingPayload(profile.resourceName)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let workouts = root["workouts"] as? [[String: Any]] else {
            throw MockWorkoutError.invalidPayload(profile.resourceName)
        }
        return workouts
    }

    private func shift(_ workout: [String: Any], by offset: TimeInterval) -> [String: Any] {
        var shifted = workout
        for key in Self.timestampKeys {
            guard let raw = workout[key] as? String, let date = Self.date(from: raw) else { continue }
            shifted[key] = ISO8601DateFormatter.hevyPlain.string(from: date.addingTimeInterval(offset))
        }
        return shifted
    }

    private static func date(from raw: String) -> Date? {
        ISO8601DateFormatter.hevyPlain.date(from: raw)
            ?? ISO8601DateFormatter.hevyFractional.date(from: raw)
    }

    /// Shared storage for the copies of one loader — the loader stays a value
    /// type, the parsed payloads are computed once.
    private final class Cache {
        var shifted: [MockWorkoutProfile: [[String: Any]]] = [:]
    }
}

#endif
