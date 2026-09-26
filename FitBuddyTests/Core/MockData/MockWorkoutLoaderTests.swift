import XCTest
@testable import FitBuddy

// Development fixture: excluded from Release builds, so no mock training
// history can reach a TestFlight binary. The payloads themselves are
// stripped from the Release bundle via EXCLUDED_SOURCE_FILE_NAMES.
#if DEBUG

/// Guards the properties the bundled mock data is supposed to have (#44,
/// #188): every payload decodes through its own source's real path, a profile
/// keeps its training frequency inside the dashboard's 90-day window, and a
/// profile built from several sources moves as one when it is re-anchored.
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

    /// Hevy's half of every profile. Strava and Polar report no sets at all —
    /// an activity *is* the effort — so the assertion is about the sessions
    /// Hevy recorded, whichever profile holds them (#188).
    func testEveryHevyWorkoutHasLoggedSets() throws {
        for profile in hevyProfiles {
            for workout in try hevyWorkouts(of: profile) {
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
        for profile in hevyProfiles {
            let volume = try totalVolume(of: hevyWorkouts(of: profile))
            XCTAssertGreaterThan(volume, 0, "\(profile.rawValue) has no countable volume")
        }
    }

    /// #27 charts training volume over the window and the AI analysis (#3) reads
    /// a trend out of it, so the fixture has to rise across the window — not
    /// only per exercise, where set and rep variation can hide the progression.
    func testVolumePerSessionTrendsUpAcrossTheWindow() throws {
        for profile in hevyProfiles {
            let workouts = try hevyWorkouts(of: profile).sorted { $0.startTime < $1.startTime }
            let third = workouts.count / 3
            let oldest = averageVolume(of: Array(workouts.prefix(third)))
            let newest = averageVolume(of: Array(workouts.suffix(third)))
            XCTAssertGreaterThan(newest, oldest * 1.05, "\(profile.rawValue) shows no volume progression")
        }
    }

    /// A logged session that counts zero volume reads as "did not train" in the
    /// dashboard — even the conditioning days carry some weighted work.
    func testEverySessionCountsSomeVolume() throws {
        for profile in hevyProfiles {
            for workout in try hevyWorkouts(of: profile) {
                XCTAssertGreaterThan(totalVolume(of: [workout]), 0, "\(workout.title) counts no volume")
            }
        }
    }

    /// Person A trains heavier and more often, so the dashboard shows a clearly
    /// different picture for the two profiles.
    func testPersonATrainsMoreVolumeThanPersonB() throws {
        let personA = try totalVolume(of: hevyWorkouts(of: .personA))
        let personB = try totalVolume(of: hevyWorkouts(of: .personB))
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

    /// US-14 AC4: the app's own recovery figures find six training days in the
    /// last seven, whatever the time of day the loader re-anchors at and
    /// wherever the device is — the reference day or the day before can hold
    /// the newest session, and the local date line can fall either side of it.
    func testOverreachedCallsForRecoveryAtAnyHourInAnyZone() throws {
        for zone in Self.zones {
            for hour in [0, 6, 12, 18, 23] {
                let metrics = try recoveryMetrics(of: .overreached, atHour: hour, in: zone)

                XCTAssertEqual(metrics.trainingDays, 6, "at \(hour):01 in \(zone)")
                XCTAssertTrue(metrics.needsRecovery, "at \(hour):01 in \(zone)")
            }
        }
    }

    /// The progression profile stays clear of the recovery threshold, so its
    /// progression is shown without a recovery card.
    func testProgressionReadyNeedsNoRecoveryAtAnyHour() throws {
        for hour in [0, 6, 12, 18, 23] {
            let metrics = try recoveryMetrics(of: .progressionReady, atHour: hour)

            XCTAssertFalse(metrics.needsRecovery, "at \(hour):01 UTC")
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

    /// The payload files are session archives, not recorded responses: a stored
    /// `page`/`page_count` would contradict every request they answer, and the
    /// loader builds Hevy's envelope per request anyway.
    ///
    /// Each file is in its own source's wire shape — Hevy's `workouts` object,
    /// optionally with the `routines` its workouts name (#233), and the bare
    /// arrays Strava and Polar return (#188).
    func testPayloadFilesCarryTheirSourcesWireShape() throws {
        for payload in MockWorkoutProfile.allCases.flatMap(\.payloads) {
            let root = try json(of: payload)
            switch payload.source {
            case .hevy:
                let object = try XCTUnwrap(root as? [String: Any], payload.resourceName)
                XCTAssertTrue(
                    Set(object.keys).isSubset(of: ["workouts", "routines"]) && object["workouts"] != nil,
                    "\(payload.resourceName) stores more than its workouts and routines"
                )
            case .strava, .polar:
                XCTAssertNotNil(root as? [[String: Any]], "\(payload.resourceName) is not an array")
            }
        }
    }

    /// Every payload is named so the Release exclusion covers it: the app
    /// target strips `mock-workouts-*.json`, and a cardio fixture named
    /// anything else would ship a training history in a TestFlight binary
    /// (#44, #188).
    func testEveryPayloadIsNamedForTheReleaseExclusion() {
        for payload in MockWorkoutProfile.allCases.flatMap(\.payloads) {
            XCTAssertTrue(payload.resourceName.hasPrefix("mock-workouts-"), payload.resourceName)
        }
    }

    /// The progression-ready profile logs against two routines (#233): every
    /// session names one, and bench press is prescribed at 3 × 3 — so the
    /// three closing sessions of 60 kg × 5 meet the 2-for-2 rule of ADR-013,
    /// and only they do.
    func testProgressionReadySessionsCarryTheirRoutineTargets() throws {
        let activities = try loader.activities(for: .progressionReady, from: .hevy)

        XCTAssertFalse(activities.isEmpty)
        XCTAssertTrue(activities.allSatisfy { $0.routineID != nil }, "a session without a routine")
        XCTAssertTrue(activities.allSatisfy { $0.routineUpdatedAt != nil }, "a routine without a snapshot date")
        let bench = try XCTUnwrap(
            activities.first { $0.title == "Upper Body" }?.exercises.first { $0.title == "Bench Press (Barbell)" }
        )
        XCTAssertEqual(bench.sets.map(\.targetReps), [8, 3, 3, 3])
        let row = try XCTUnwrap(
            activities.first { $0.title == "Upper Body" }?.exercises.first { $0.title == "Bent Over Row (Barbell)" }
        )
        XCTAssertEqual(row.sets.map(\.targetReps), [8, 8, 8])
    }

    /// The plateau profile (#235) logs every session against one routine
    /// that prescribes three of its four exercises — the fourth is the
    /// not-checkable case, so it has no targets by design.
    func testPlateauSessionsCarryTargetsForThreeOfFourExercises() throws {
        let activities = try loader.activities(for: .plateau, from: .hevy)

        XCTAssertEqual(activities.count, 16)
        XCTAssertTrue(activities.allSatisfy { $0.routineID != nil }, "a session without a routine")
        let newest = try XCTUnwrap(activities.first)
        let targets = Dictionary(uniqueKeysWithValues: newest.exercises.map { ($0.title, $0.sets.map(\.targetReps)) })
        XCTAssertEqual(targets["Squat (Barbell)"], [8, 3, 3, 3, 3])
        XCTAssertEqual(targets["Bench Press (Barbell)"], [5, 5, 5])
        XCTAssertEqual(targets["Lateral Raise (Dumbbell)"], [10, 10, 10])
        XCTAssertEqual(targets["Seated Row (Cable)"], [nil, nil, nil])
    }

    /// Every plateau session starts at 12:00 UTC, like the cross-source
    /// profiles: one wall clock keeps the day counts in every zone.
    func testThePlateauProfileSharesOneWallClock() throws {
        let clocks = Set(try loader.activities(for: .plateau, from: .hevy).map {
            Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: $0.startTime).hour
        })
        XCTAssertEqual(clocks, [12])
    }

    /// The other Hevy profiles log freely: no routine, no targets — the
    /// common case, and the one the rule reads as not checkable.
    func testTheOtherHevyProfilesCarryNoTargets() throws {
        for profile in [MockWorkoutProfile.personA, .personB, .overreached, .mixed, .overreachedMixed] {
            let activities = try loader.activities(for: profile, from: .hevy)
            XCTAssertTrue(activities.allSatisfy { $0.routineID == nil }, profile.rawValue)
            XCTAssertTrue(
                activities.flatMap(\.exercises).flatMap(\.sets).allSatisfy { $0.targetReps == nil },
                profile.rawValue
            )
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

    func testMissingPayloadIsReported() throws {
        // A bundle without the payloads — the "app bundle is broken" path.
        let empty = MockWorkoutLoader(bundle: Bundle(for: XCTestCase.self), now: { self.now })
        let name = try XCTUnwrap(MockWorkoutProfile.personA.payloads.first).resourceName
        XCTAssertThrowsError(try empty.workouts(for: .personA)) { error in
            XCTAssertEqual(error as? MockWorkoutError, .missingPayload(name))
        }
    }

    /// A profile that records no strength training has no Hevy page to serve.
    /// Answering with an empty one would claim the runner has a gym half and
    /// trained nothing in it (#188).
    func testAHevyPageIsRefusedForAProfileWithoutOne() {
        XCTAssertThrowsError(try loader.pageData(for: .runner)) { error in
            XCTAssertEqual(
                error as? MockWorkoutError,
                .noPayload(profile: MockWorkoutProfile.runner.rawValue, source: .hevy)
            )
        }
        XCTAssertThrowsError(try loader.activities(for: .mixed, from: .polar)) { error in
            XCTAssertEqual(
                error as? MockWorkoutError,
                .noPayload(profile: MockWorkoutProfile.mixed.rawValue, source: .polar)
            )
        }
    }

    // MARK: - Cross-source profiles (#188)

    /// Every profile caches under the sources it declares, and under no other
    /// — the seeding path writes one source at a time.
    func testEachProfileCachesUnderTheSourcesItDeclares() throws {
        for profile in MockWorkoutProfile.allCases {
            let activities = try loader.activities(for: profile)
            XCTAssertEqual(
                Set(activities.map(\.source)),
                Set(profile.payloads.map(\.source)),
                profile.rawValue
            )
            let counted = try profile.payloads
                .map { try loader.activities(for: profile, from: $0.source).count }
                .reduce(0, +)
            XCTAssertEqual(counted, activities.count, profile.rawValue)
        }
    }

    /// The runner's window is endurance and nothing else: every session is
    /// mapped to a running kind by `StravaActivityDTO`, and none of them
    /// counts a kilogram.
    func testTheRunnerRecordsNothingButRunning() throws {
        let summaries = try summaries(of: .runner)

        XCTAssertEqual(summaries.count, 32)
        XCTAssertTrue(summaries.allSatisfy { $0.source == .strava })
        XCTAssertEqual(Set(summaries.map(\.kind)), [.run])
        XCTAssertTrue(summaries.allSatisfy(\.isCardio))
        XCTAssertTrue(summaries.allSatisfy { $0.volumeKg == 0 })
    }

    /// The figures US-15 reports come out of the real mapping, not out of the
    /// fixture: distance and moving time off the set, heart rate, ascent,
    /// speed and effort out of `CardioMetrics`.
    func testTheRunnerCarriesTheCardioMetricsStravaSends() throws {
        let summaries = try summaries(of: .runner)
        let trail = try XCTUnwrap(summaries.first { $0.title == "Long trail run" })

        XCTAssertEqual(trail.kind, .run)
        XCTAssertEqual(try XCTUnwrap(trail.distanceMeters), 17_000, accuracy: 1)
        XCTAssertNotNil(trail.durationSeconds)
        let cardio = try XCTUnwrap(trail.cardio)
        XCTAssertEqual(cardio.averageHeartRate, 148)
        XCTAssertEqual(cardio.maxHeartRate, 167)
        XCTAssertEqual(cardio.elevationGainMeters, 390)
        XCTAssertEqual(try XCTUnwrap(cardio.averageSpeedMetersPerSecond), 2.78, accuracy: 0.01)
        XCTAssertEqual(cardio.relativeEffort, 148)

        // The shake-out run wore no strap: its cells have to be absent rather
        // than zero (US-15 AC7).
        let shakeOut = try XCTUnwrap(summaries.first { $0.title == "Shake-out run" })
        XCTAssertNil(shakeOut.cardio?.averageHeartRate)
        XCTAssertNil(shakeOut.cardio?.relativeEffort)
    }

    /// Four runs a week, never six days in seven — the runner is a dense week,
    /// not a recovery week. The week's offsets all sit inside the five days a
    /// seven-day span holds however the re-anchoring falls, and every run
    /// starts at the same wall clock, so the count is four at any hour in any
    /// zone rather than sliding between three and four (#188 review).
    func testTheRunnerTrainsFourDaysAWeekAtAnyHourInAnyZone() throws {
        for zone in Self.zones {
            for hour in [0, 6, 12, 18, 23] {
                let metrics = try recoveryMetrics(of: .runner, atHour: hour, in: zone)

                XCTAssertEqual(metrics.trainingDays, 4, "at \(hour):01 in \(zone)")
                XCTAssertFalse(metrics.needsRecovery, "at \(hour):01 in \(zone)")
                XCTAssertNil(metrics.averageRPE, "a run logs no RPE")
                XCTAssertNotNil(metrics.averageHeartRate)
            }
        }
    }

    /// The mixed week is what US-15 AC2 is written about: three lifts, three
    /// endurance sessions, and two days that carried both.
    ///
    /// In every zone, because an overlap day is the one figure a zone shift
    /// could take apart: a lift and a run land on one local day only as long
    /// as the shift moves both of them (#188 review).
    func testTheMixedProfileOverlapsTwoDaysAWeekInAnyZone() throws {
        for zone in Self.zones {
            let calendar = Self.calendar(in: zone)
            let reference = calendar.startOfDay(for: now).addingTimeInterval(13 * 3_600)
            let workouts = try MockWorkoutLoader(bundle: Bundle(for: Workout.self), now: { reference })
                .workouts(for: .mixed)
            let summaries = workouts.map(WorkoutSummary.init(workout:))
            let week = RecoveryMetrics.lastSevenDaysSessions(
                in: summaries,
                now: reference,
                calendar: calendar
            )
            let strength = Set(week.filter { !$0.isCardio }.map { calendar.startOfDay(for: $0.startTime) })
            let endurance = Set(week.filter(\.isCardio).map { calendar.startOfDay(for: $0.startTime) })

            XCTAssertEqual(strength.count, 3, zone)
            XCTAssertEqual(endurance.count, 3, zone)
            XCTAssertEqual(strength.intersection(endurance).count, 2, zone)
            XCTAssertEqual(strength.union(endurance).count, 4, "four training days, no recovery week — \(zone)")
            XCTAssertEqual(Set(summaries.map(\.source)), [.hevy, .strava], zone)
        }
    }

    /// The whole profile moves by one offset. Anchored per file, the Hevy and
    /// the Strava half would slide against each other and the overlap days
    /// would disappear — silently, since both halves would still look sane.
    func testAProfileMovesAsOneWhateverTheClock() throws {
        let later = MockWorkoutLoader(bundle: Bundle(for: Workout.self), now: {
            self.now.addingTimeInterval(200 * 86_400)
        })

        let base = try summaries(of: .mixed).map { $0.startTime }.sorted()
        let shifted = try later.activities(for: .mixed)
            .map(\.startTime)
            .sorted()

        XCTAssertEqual(base.count, shifted.count)
        let offsets = Set(zip(base, shifted).map { $1.timeIntervalSince($0) })
        XCTAssertEqual(offsets.count, 1, "the sources moved by different offsets")
        XCTAssertEqual(try XCTUnwrap(offsets.first).truncatingRemainder(dividingBy: 86_400), 0)
    }

    /// US-15 AC3: six of the last seven days, and no single source shows it —
    /// three lifts, two runs and one ride. This is the case the recovery rule
    /// only catches because #184 counts across sources.
    func testTheOverreachedMixedWeekIsSixDaysAcrossThreeSources() throws {
        for zone in Self.zones {
            for hour in [0, 6, 12, 18, 23] {
                let metrics = try recoveryMetrics(of: .overreachedMixed, atHour: hour, in: zone)

                XCTAssertEqual(metrics.trainingDays, 6, "at \(hour):01 in \(zone)")
                XCTAssertEqual(metrics.sessions, 6, "at \(hour):01 in \(zone)")
                XCTAssertTrue(metrics.needsRecovery, "at \(hour):01 in \(zone)")
                XCTAssertEqual(metrics.suggestedRestHours, 48)
                XCTAssertEqual(try XCTUnwrap(metrics.averageRPE), 8.5, accuracy: 0.0001)
                XCTAssertNotNil(metrics.averageHeartRate, "the runs and the ride wore a strap")
            }
        }
    }

    func testNoSingleSourceOfTheOverreachedMixedWeekReachesTheThreshold() throws {
        let week = RecoveryMetrics.lastSevenDaysSessions(
            in: try summaries(of: .overreachedMixed),
            now: now,
            calendar: Self.utc
        )
        XCTAssertEqual(Set(week.map(\.source)), [.hevy, .strava, .polar])

        for source in ConnectorSource.allCases {
            let days = Set(week.filter { $0.source == source }
                .map { Self.utc.startOfDay(for: $0.startTime) })
            XCTAssertLessThan(days.count, RecoveryMetrics.recoveryTrainingDays, source.rawValue)
        }
    }

    /// The property the zone-proof day counts rest on: every session of the
    /// three cross-source profiles starts at the same wall clock, so a zone
    /// shift moves all of them across the local date line together or none of
    /// them (#188 review).
    ///
    /// Asserted on the payloads rather than trusted, because it is invisible:
    /// a fixture edited to a "more realistic" evening ride would still load,
    /// still decode and still read correctly near UTC, and would only fail
    /// somewhere in the Pacific.
    func testTheCrossSourceProfilesShareOneWallClock() throws {
        for profile in [MockWorkoutProfile.runner, .mixed, .overreachedMixed, .progressionReady, .overreached, .plateau] {
            let clocks = Set(try loader.workouts(for: profile).map {
                Self.utc.dateComponents([.hour, .minute, .second], from: $0.startTime)
            })
            XCTAssertEqual(clocks.count, 1, "\(profile.rawValue) spreads over \(clocks.count) times of day")
        }
    }

    /// The strength profiles carry their endurance sessions on days that
    /// already carry a lift (#262): no profile gains a training day, so the
    /// count each one exists to prove — three, six, two — holds in every
    /// zone and at every hour, and the recovery figures read all three
    /// sources.
    func testTheStrengthProfilesKeepTheirTrainingDaysWithCardioOnLiftDays() throws {
        for (profile, days) in [(MockWorkoutProfile.progressionReady, 3), (.overreached, 6), (.plateau, 2)] {
            for zone in Self.zones {
                for hour in [0, 6, 12, 18, 23] {
                    let calendar = Self.calendar(in: zone)
                    let reference = calendar.startOfDay(for: now).addingTimeInterval(Double(hour) * 3_600 + 60)
                    let workouts = try MockWorkoutLoader(bundle: Bundle(for: Workout.self), now: { reference })
                        .workouts(for: profile)
                    let week = RecoveryMetrics.lastSevenDaysSessions(
                        in: workouts.map(WorkoutSummary.init(workout:)),
                        now: reference,
                        calendar: calendar
                    )
                    let day = { (summary: WorkoutSummary) in calendar.startOfDay(for: summary.startTime) }
                    let lifts = Set(week.filter { $0.source == .hevy }.map(day))
                    let cardio = Set(week.filter { $0.source.isEnduranceSource }.map(day))
                    XCTAssertEqual(lifts.count, days, "\(profile.rawValue) at \(hour):01 in \(zone)")
                    XCTAssertTrue(cardio.isSubset(of: lifts), "\(profile.rawValue): cardio on a day without a lift, \(zone)")
                    XCTAssertEqual(Set(week.map(\.source)), [.hevy, .strava, .polar], "\(profile.rawValue) in \(zone)")
                    XCTAssertNotNil(try recoveryMetrics(of: profile, atHour: hour, in: zone).averageHeartRate, profile.rawValue)
                }
            }
        }
    }

    /// One Polar ride is recorded two hours east of UTC, so the loader's
    /// wall-clock path — resolve the local time by its offset, move the local
    /// string by whole days, keep the offset — is actually run rather than
    /// being a no-op over a payload of zeroes (#188 review).
    func testAPolarRideCarriesANonZeroUTCOffset() throws {
        let payload = try XCTUnwrap(
            MockWorkoutProfile.overreachedMixed.payloads.first { $0.source == .polar }
        )
        let entries = try XCTUnwrap(json(of: payload) as? [[String: Any]])
        let offsets = entries.map { $0["start_time_utc_offset"] as? Int }

        XCTAssertEqual(offsets.compactMap { $0 }.count, entries.count, "an entry records no offset")
        XCTAssertTrue(offsets.contains { ($0 ?? 0) != 0 }, "no entry exercises the offset path")
    }

    /// Polar reports no sets at all: its distance and duration travel in the
    /// cardio block, and the cache has to read them back from there.
    func testThePolarRidesCarryTheirFiguresInTheCardioBlock() throws {
        let rides = try summaries(of: .overreachedMixed).filter { $0.source == .polar }

        XCTAssertEqual(rides.count, 9)
        for ride in rides {
            XCTAssertEqual(ride.kind, .ride)
            XCTAssertEqual(ride.exerciseCount, 0)
            XCTAssertGreaterThan(try XCTUnwrap(ride.distanceMeters), 0)
            XCTAssertGreaterThan(try XCTUnwrap(ride.durationSeconds), 0)
            XCTAssertNotNil(ride.cardio?.averageHeartRate)
            XCTAssertNotNil(ride.cardio?.trainingLoad)
        }
    }

    // MARK: - Helpers

    private static let utc = calendar(in: "UTC")

    /// The working sets of every bench press session, oldest first.
    private func benchSessions(of profile: MockWorkoutProfile) throws -> [[ExerciseSet]] {
        try loader.workouts(for: profile)
            .sorted { $0.startTime < $1.startTime }
            .flatMap(\.exercises)
            .filter { $0.title == "Bench Press (Barbell)" }
            .map { $0.sets.filter { $0.type.countsTowardsVolume } }
    }

    /// Time zones the day counts have to survive, as the whole span a device
    /// can be in: a day behind UTC, on it, and most of a day ahead of it.
    ///
    /// Not decoration. Every figure these profiles exist to prove is a count of
    /// *local* days, and a profile whose sources sit at different times of day
    /// only holds near UTC — shift far enough and one source crosses the local
    /// date line while the others do not (#188 review). The sessions therefore
    /// share one wall clock, and this is what pins it.
    private static let zones = [
        "Pacific/Honolulu",   // UTC−10
        "America/Los_Angeles", // UTC−8/−7
        "UTC",
        "Europe/Zurich",      // UTC+1/+2 — the team's own
        "Pacific/Kiritimati", // UTC+14, the far end
    ]

    /// `RecoveryMetrics` over the profile as a loader re-anchored at
    /// `hour`:01 on the reference day, in `zone`, would cache it — the rule the
    /// analysis applies, not a copy of it.
    ///
    /// The details are handed over as well since #188, so the mean RPE of a
    /// cross-source week is the figure the recovery card would carry rather
    /// than a `nil` the helper produced.
    private func recoveryMetrics(
        of profile: MockWorkoutProfile,
        atHour hour: Int,
        in zone: String = "UTC"
    ) throws -> RecoveryMetrics {
        let calendar = Self.calendar(in: zone)
        let reference = calendar.startOfDay(for: now).addingTimeInterval(Double(hour) * 3_600 + 60)
        let workouts = try MockWorkoutLoader(bundle: Bundle(for: Workout.self), now: { reference })
            .workouts(for: profile)
        return RecoveryMetrics(
            summaries: workouts.map(WorkoutSummary.init(workout:)),
            details: workouts.map(WorkoutDetail.init(workout:)),
            now: reference,
            calendar: calendar
        )
    }

    private static func calendar(in zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    /// The profiles that record strength training — everything asserted about
    /// Hevy's volume, its sets and its pages is about these (#188).
    private var hevyProfiles: [MockWorkoutProfile] {
        MockWorkoutProfile.allCases.filter { $0.hevyPayload != nil }
    }

    /// The Hevy half of a profile, as cache models.
    private func hevyWorkouts(of profile: MockWorkoutProfile) throws -> [Workout] {
        try loader.activities(for: profile, from: .hevy).map { $0.makeWorkout() }
    }

    /// The whole profile, across every source, as the cache would summarise it.
    private func summaries(of profile: MockWorkoutProfile) throws -> [WorkoutSummary] {
        try loader.workouts(for: profile).map(WorkoutSummary.init(workout:))
    }

    /// One payload file's raw JSON, straight off the bundle.
    private func json(of payload: MockWorkoutPayload) throws -> Any {
        let url = try XCTUnwrap(Bundle(for: Workout.self)
            .url(forResource: payload.resourceName, withExtension: "json"))
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
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
