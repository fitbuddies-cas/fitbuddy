import XCTest
@testable import FitBuddy

/// Guards the two properties the bundled mock data is supposed to have (#44):
/// it decodes through the real Hevy path, and each profile keeps its training
/// frequency inside the dashboard's 90-day window.
final class MockWorkoutLoaderTests: XCTestCase {
    /// Fixed reference point — every assertion is relative to it.
    private let now = Date(timeIntervalSince1970: 1_788_000_000)
    private var loader: MockWorkoutLoader!

    override func setUp() {
        super.setUp()
        loader = MockWorkoutLoader(bundle: Bundle(for: Workout.self), now: { self.now })
    }

    // MARK: - Payload integrity

    func testEveryProfileLoads() throws {
        for profile in MockWorkoutProfile.allCases {
            let workouts = try loader.workouts(for: profile)
            XCTAssertFalse(workouts.isEmpty, "\(profile.rawValue) has no workouts")
        }
    }

    func testWorkoutIDsAreUnique() throws {
        for profile in MockWorkoutProfile.allCases {
            let ids = try loader.workouts(for: profile).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(profile.rawValue) repeats a workout id")
        }
    }

    func testEveryWorkoutHasLoggedSets() throws {
        for profile in MockWorkoutProfile.allCases {
            for workout in try loader.workouts(for: profile) {
                XCTAssertFalse(workout.exercises.isEmpty, "\(workout.title) has no exercises")
                for exercise in workout.exercises {
                    XCTAssertFalse(exercise.sets.isEmpty, "\(exercise.title) has no sets")
                }
                XCTAssertNotNil(workout.endTime)
                XCTAssertGreaterThan(workout.endTime ?? workout.startTime, workout.startTime)
            }
        }
    }

    /// The dashboard's volume metric (#26) only counts non-warm-up weighted
    /// sets — mock data has to produce a non-zero number there.
    func testProfilesProduceTrainingVolume() throws {
        for profile in MockWorkoutProfile.allCases {
            let volume = try totalVolume(of: loader.workouts(for: profile))
            XCTAssertGreaterThan(volume, 0, "\(profile.rawValue) has no countable volume")
        }
    }

    /// Person A trains heavier and more often, so the dashboard shows a clearly
    /// different picture for the two profiles.
    func testPersonATrainsMoreVolumeThanPersonB() throws {
        let personA = try totalVolume(of: loader.workouts(for: .personA))
        let personB = try totalVolume(of: loader.workouts(for: .personB))
        XCTAssertGreaterThan(personA, personB)
    }

    /// Warm-up, dropset and failure sets all appear, so views and metrics meet
    /// every `SetType` they have to handle.
    func testSetTypesCoverTheDashboardCases() throws {
        let types = try Set(loader.workouts(for: .personA)
            .flatMap(\.exercises)
            .flatMap(\.sets)
            .map(\.type))
        XCTAssertTrue(types.isSuperset(of: [.normal, .warmup, .dropset, .failure]))
    }

    /// Cardio sets carry distance and duration instead of weight and reps —
    /// the optional-metric case of `HevySetDTO`.
    func testCardioSetsCarryDistanceAndDuration() throws {
        let cardioSets = try loader.workouts(for: .personA)
            .flatMap(\.exercises)
            .filter { $0.title == "Treadmill Running" || $0.title == "Rowing Machine" }
            .flatMap(\.sets)
        XCTAssertFalse(cardioSets.isEmpty)
        for set in cardioSets {
            XCTAssertNotNil(set.distanceMeters)
            XCTAssertNotNil(set.durationSeconds)
            XCTAssertNil(set.weightKg)
        }
    }

    func testExercisesCoverSeveralMuscleGroups() throws {
        let templateIDs = try Set(loader.workouts(for: .personA)
            .flatMap(\.exercises)
            .compactMap(\.templateID))
        XCTAssertGreaterThanOrEqual(templateIDs.count, 15)
    }

    // MARK: - Training frequency

    func testPersonATrainsAboutFiveTimesAWeek() throws {
        let sessions = try sessionsPerWeek(of: loader.workouts(for: .personA))
        XCTAssertEqual(sessions, 5, accuracy: 0.5)
    }

    func testPersonBTrainsAboutTwiceAWeek() throws {
        let sessions = try sessionsPerWeek(of: loader.workouts(for: .personB))
        XCTAssertEqual(sessions, 2, accuracy: 0.5)
    }

    // MARK: - Re-anchoring

    func testWorkoutsFallIntoTheDashboardWindow() throws {
        let windowStart = now.addingTimeInterval(-90 * 86_400)
        for profile in MockWorkoutProfile.allCases {
            for workout in try loader.workouts(for: profile) {
                XCTAssertGreaterThanOrEqual(workout.startTime, windowStart, "\(workout.title) is older than 90 days")
                XCTAssertLessThanOrEqual(workout.startTime, now, "\(workout.title) lies in the future")
            }
        }
    }

    /// The newest session is recent enough for a dashboard that talks about the
    /// last workout.
    func testNewestWorkoutIsWithinTheLastDay() throws {
        for profile in MockWorkoutProfile.allCases {
            let newest = try XCTUnwrap(loader.workouts(for: profile).map(\.startTime).max())
            XCTAssertGreaterThan(newest, now.addingTimeInterval(-86_400))
        }
    }

    /// The payloads carry fixed dates; a loader reading them years later has to
    /// return the same window, only moved.
    func testWindowMovesWithTheClock() throws {
        let later = now.addingTimeInterval(365 * 86_400)
        let laterLoader = MockWorkoutLoader(bundle: Bundle(for: Workout.self), now: { later })

        let base = try loader.workouts(for: .personB).map(\.startTime).sorted()
        let shifted = try laterLoader.workouts(for: .personB).map(\.startTime).sorted()

        XCTAssertEqual(base.count, shifted.count)
        // Whole-day shift, so every session keeps its spacing and time of day.
        let offsets = Set(zip(base, shifted).map { $1.timeIntervalSince($0) })
        XCTAssertEqual(offsets.count, 1)
        let offset = try XCTUnwrap(offsets.first)
        XCTAssertEqual(offset.truncatingRemainder(dividingBy: 86_400), 0)
        XCTAssertGreaterThan(offset, 0)
    }

    // MARK: - Wire format

    func testPagesLookLikeHevyPages() throws {
        let data = try loader.pageData(for: .personA, page: 1, pageSize: MockWorkoutLoader.pageSize)
        let page = try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)

        XCTAssertEqual(page.page, 1)
        XCTAssertGreaterThan(page.pageCount, 1)
        XCTAssertEqual(page.workouts.count, MockWorkoutLoader.pageSize)
    }

    /// Paging through a profile yields its whole history exactly once — the
    /// property a stubbed `HevyService` walk depends on.
    func testPagingCoversEveryWorkoutOnce() throws {
        let all = try loader.workouts(for: .personB).map(\.id)
        var collected: [String] = []
        var page = 1

        while true {
            let data = try loader.pageData(for: .personB, page: page, pageSize: MockWorkoutLoader.pageSize)
            let decoded = try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)
            collected.append(contentsOf: decoded.workouts.map(\.id))
            guard page < decoded.pageCount else { break }
            page += 1
        }

        XCTAssertEqual(collected, all)
    }

    /// Hevy serves newest first; the mock payloads have to do the same, or the
    /// service's "stop at the first page outside the window" walk sees an order
    /// it never gets from the API.
    func testWorkoutsAreOrderedNewestFirst() throws {
        for profile in MockWorkoutProfile.allCases {
            let starts = try loader.workouts(for: profile).map(\.startTime)
            XCTAssertEqual(starts, starts.sorted(by: >), "\(profile.rawValue) is not newest first")
        }
    }

    func testOvershootingPageNumberReturnsTheLastPage() throws {
        let data = try loader.pageData(for: .personB, page: 999, pageSize: MockWorkoutLoader.pageSize)
        let page = try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)

        XCTAssertEqual(page.page, page.pageCount)
        XCTAssertFalse(page.workouts.isEmpty)
    }

    func testMissingPayloadIsReported() {
        // A bundle without the payloads — the "app bundle is broken" path.
        let empty = MockWorkoutLoader(bundle: Bundle(for: XCTestCase.self), now: { self.now })
        XCTAssertThrowsError(try empty.workouts(for: .personA)) { error in
            XCTAssertEqual(error as? MockWorkoutError, .missingPayload(MockWorkoutProfile.personA.resourceName))
        }
    }

    // MARK: - Helpers

    /// Dashboard volume rule (#26): weight × reps, warm-ups excluded.
    private func totalVolume(of workouts: [Workout]) -> Double {
        workouts
            .flatMap(\.exercises)
            .flatMap(\.sets)
            .filter { $0.type.countsTowardsVolume }
            .reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
    }

    /// Distinct training days per week across the covered window.
    private func sessionsPerWeek(of workouts: [Workout]) -> Double {
        let starts = workouts.map(\.startTime).sorted()
        guard let first = starts.first, let last = starts.last, last > first else { return 0 }
        let weeks = last.timeIntervalSince(first) / (7 * 86_400)
        return Double(starts.count) / weeks
    }
}
