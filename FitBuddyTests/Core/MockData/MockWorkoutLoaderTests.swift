import XCTest
@testable import FitBuddy

// Development fixture: excluded from Release builds, so no mock training
// history can reach a TestFlight binary. The payloads themselves are
// stripped from the Release bundle via EXCLUDED_SOURCE_FILE_NAMES.
#if DEBUG

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

    /// #27 charts training volume over the window and the AI analysis (#3) reads
    /// a trend out of it, so the fixture has to rise across the window — not
    /// only per exercise, where set and rep variation can hide the progression.
    func testVolumePerSessionTrendsUpAcrossTheWindow() throws {
        for profile in MockWorkoutProfile.allCases {
            let workouts = try loader.workouts(for: profile).sorted { $0.startTime < $1.startTime }
            let third = workouts.count / 3
            let oldest = averageVolume(of: Array(workouts.prefix(third)))
            let newest = averageVolume(of: Array(workouts.suffix(third)))
            XCTAssertGreaterThan(newest, oldest * 1.05, "\(profile.rawValue) shows no volume progression")
        }
    }

    /// A logged session that counts zero volume reads as "did not train" in the
    /// dashboard — even the conditioning days carry some weighted work.
    func testEverySessionCountsSomeVolume() throws {
        for profile in MockWorkoutProfile.allCases {
            for workout in try loader.workouts(for: profile) {
                XCTAssertGreaterThan(totalVolume(of: [workout]), 0, "\(workout.title) counts no volume")
            }
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

    // MARK: - Analysis profiles (#179)

    /// US-14 AC2: bench press ends on three sessions at 60 kg × 5, every
    /// working set at RPE 7 or lower, after a lighter one — a load the lift
    /// grew into rather than one it started on.
    func testProgressionReadyEndsBenchOnThreeCleanSessionsAtSixtyKilos() throws {
        let sessions = try benchSessions(of: .progressionReady)
        XCTAssertGreaterThan(sessions.count, 3)

        for sets in sessions.suffix(3) {
            XCTAssertFalse(sets.isEmpty)
            for set in sets {
                XCTAssertEqual(set.weightKg, 60)
                XCTAssertEqual(set.reps, 5)
                XCTAssertLessThanOrEqual(try XCTUnwrap(set.rpe), 7)
            }
        }
        let before = try XCTUnwrap(sessions.dropLast(3).last)
        XCTAssertTrue(before.allSatisfy { ($0.weightKg ?? 0) < 60 })
    }

    /// US-14 AC4: six training days in the seven the recovery figures count,
    /// whatever the time of day the loader re-anchors at — the reference day
    /// or the day before can hold the newest session.
    func testOverreachedTrainsOnSixOfTheLastSevenDaysAtAnyHour() throws {
        for hour in [0, 6, 12, 18, 23] {
            let reference = utcMidnight(of: now).addingTimeInterval(Double(hour) * 3_600 + 60)
            let workouts = try MockWorkoutLoader(bundle: Bundle(for: Workout.self), now: { reference })
                .workouts(for: .overreached)

            XCTAssertEqual(trainingDaysInLastSeven(of: workouts, endingAt: reference), 6, "at \(hour):01 UTC")
        }
    }

    /// The progression profile stays clear of the recovery threshold, so its
    /// progression is shown without a recovery card.
    func testProgressionReadyStaysBelowTheRecoveryThresholdAtAnyHour() throws {
        for hour in [0, 6, 12, 18, 23] {
            let reference = utcMidnight(of: now).addingTimeInterval(Double(hour) * 3_600 + 60)
            let workouts = try MockWorkoutLoader(bundle: Bundle(for: Workout.self), now: { reference })
                .workouts(for: .progressionReady)

            XCTAssertLessThan(trainingDaysInLastSeven(of: workouts, endingAt: reference), 6, "at \(hour):01 UTC")
        }
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

    /// The clock is read once per loader, not once per call — a page walk that
    /// runs across midnight must not shift its pages a day against each other.
    func testOneLoaderReadsTheClockOnce() throws {
        var reads = 0
        let advancing: () -> Date = {
            defer { reads += 1 }
            return self.now.addingTimeInterval(Double(reads) * 86_400)
        }
        let walking = MockWorkoutLoader(bundle: Bundle(for: Workout.self), now: advancing)

        var collected: [Date] = []
        var page = 1
        while true {
            let data = try walking.pageData(for: .personB, page: page, pageSize: MockWorkoutLoader.pageSize)
            let decoded = try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)
            collected.append(contentsOf: decoded.workouts.map(\.startTime))
            guard page < decoded.pageCount else { break }
            page += 1
        }

        XCTAssertEqual(reads, 1)
        // Same instant for every page, so the walk matches a loader on a fixed clock.
        XCTAssertEqual(collected, try loader.workouts(for: .personB).map(\.startTime))
    }

    // MARK: - Wire format

    /// The payload files are workout archives, not recorded responses: a stored
    /// `page`/`page_count` would contradict every request they answer, and the
    /// loader builds the envelope per request anyway.
    func testPayloadFilesCarryNoPageEnvelope() throws {
        for profile in MockWorkoutProfile.allCases {
            let url = try XCTUnwrap(Bundle(for: Workout.self)
                .url(forResource: profile.resourceName, withExtension: "json"))
            let root = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            )
            XCTAssertEqual(Set(root.keys), ["workouts"], "\(profile.rawValue) stores more than its workouts")
        }
    }

    func testPagesLookLikeHevyPages() throws {
        let data = try loader.pageData(for: .personA, page: 1, pageSize: MockWorkoutLoader.pageSize)
        let page = try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)

        XCTAssertEqual(page.page, 1)
        XCTAssertGreaterThan(page.pageCount, 1)
        XCTAssertEqual(page.workouts.count, MockWorkoutLoader.pageSize)
    }

    /// Paging through a profile yields its whole history exactly once — the
    /// property a stubbed `HevyConnector` walk depends on.
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

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func utcMidnight(of date: Date) -> Date {
        Self.utc.startOfDay(for: date)
    }

    /// The working sets of every bench press session, oldest first.
    private func benchSessions(of profile: MockWorkoutProfile) throws -> [[ExerciseSet]] {
        try loader.workouts(for: profile)
            .sorted { $0.startTime < $1.startTime }
            .flatMap(\.exercises)
            .filter { $0.title == "Bench Press (Barbell)" }
            .map { $0.sets.filter { $0.type.countsTowardsVolume } }
    }

    /// Distinct UTC days with a session in the seven days the recovery figures
    /// count (`RecoveryMetrics.lastSevenDaysSessions`).
    private func trainingDaysInLastSeven(of workouts: [Workout], endingAt reference: Date) -> Int {
        let start = AnalysisWindow.weekStart(0, endingAt: reference, calendar: Self.utc)
        let end = start.addingTimeInterval(7 * 86_400)
        return Set(workouts
            .map(\.startTime)
            .filter { $0 >= start && $0 < end }
            .map { Self.utc.startOfDay(for: $0) }
        ).count
    }

    /// Dashboard volume rule (#26): weight × reps, warm-ups excluded.
    private func totalVolume(of workouts: [Workout]) -> Double {
        workouts
            .flatMap(\.exercises)
            .flatMap(\.sets)
            .filter { $0.type.countsTowardsVolume }
            .reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
    }

    private func averageVolume(of workouts: [Workout]) -> Double {
        guard !workouts.isEmpty else { return 0 }
        return totalVolume(of: workouts) / Double(workouts.count)
    }

    /// Distinct training days per week across the covered window.
    private func sessionsPerWeek(of workouts: [Workout]) -> Double {
        let starts = workouts.map(\.startTime).sorted()
        guard let first = starts.first, let last = starts.last, last > first else { return 0 }
        let weeks = last.timeIntervalSince(first) / (7 * 86_400)
        return Double(starts.count) / weeks
    }
}

#endif
