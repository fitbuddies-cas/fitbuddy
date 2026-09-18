import XCTest
@testable import FitBuddy

/// `RecoveryMetrics` (#175, #184): the last seven days as the app counts them —
/// strength and endurance together since #184 — and the rest rule.
final class RecoveryMetricsTests: XCTestCase {
    private var calendar: Calendar!
    /// 2025-06-15 12:26:40 UTC.
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    }

    // MARK: - Rest rule

    func testSuggestedRestFollowsTrainingDays() {
        XCTAssertEqual(RecoveryMetrics.suggestedRestHours(trainingDays: 7), 72)
        XCTAssertEqual(RecoveryMetrics.suggestedRestHours(trainingDays: 6), 48)
        XCTAssertEqual(RecoveryMetrics.suggestedRestHours(trainingDays: 5), 24)
        XCTAssertEqual(RecoveryMetrics.suggestedRestHours(trainingDays: 0), 24)
    }

    func testNeedsRecoveryFromSixTrainingDays() {
        XCTAssertFalse(RecoveryMetrics(sessions: 9, trainingDays: 5, averageRPE: nil).needsRecovery)
        XCTAssertTrue(RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil).needsRecovery)
        XCTAssertTrue(RecoveryMetrics(sessions: 7, trainingDays: 7, averageRPE: nil).needsRecovery)
    }

    // MARK: - Counting

    /// Today and the six days before it; two sessions on one day are one
    /// training day but two sessions.
    func testCountsSessionsAndTrainingDaysOfTheLastSevenDays() {
        let summaries = [0, 1, 2, 3, 4, 5].map { summary("w\($0)", daysAgo: $0) }
            + [summary("same-day", daysAgo: 2), summary("too-old", daysAgo: 7)]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.sessions, 7)
        XCTAssertEqual(metrics.trainingDays, 6)
        XCTAssertTrue(metrics.needsRecovery)
        XCTAssertEqual(metrics.suggestedRestHours, 48)
    }

    /// The reversal #184 is about: a run counts towards the sessions and the
    /// training days, where #183 still left it out (US-15 AC3). Replaces
    /// `testEnduranceSessionsAreNotCounted`, whose premise this change undoes.
    func testEnduranceSessionsAreCounted() {
        let summaries = [
            summary("lift", daysAgo: 1),
            summary("run", daysAgo: 2, source: .strava, kind: .run),
        ]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.sessions, 2)
        XCTAssertEqual(metrics.trainingDays, 2)
    }

    /// The issue's first acceptance criterion: 3 strength sessions and 4 runs
    /// on 6 distinct days are 6 training days, so the recovery hint is due and
    /// the rest rule lands on 48 h.
    func testThreeStrengthAndFourCardioSessionsOnSixDaysReachTheThreshold() {
        let summaries = [
            summary("lift-0", daysAgo: 0),
            summary("lift-1", daysAgo: 1),
            summary("lift-2", daysAgo: 2),
            summary("run-2", daysAgo: 2, source: .strava, kind: .run),
            summary("run-3", daysAgo: 3, source: .strava, kind: .run),
            summary("run-4", daysAgo: 4, source: .strava, kind: .run),
            summary("run-5", daysAgo: 5, source: .polar, kind: .run),
        ]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.sessions, 7)
        XCTAssertEqual(metrics.trainingDays, 6)
        XCTAssertTrue(metrics.needsRecovery)
        XCTAssertEqual(metrics.suggestedRestHours, 48)
    }

    /// The mixed week of the brief: 4 strength sessions and 2 runs on 6 days.
    func testAMixedWeekOfFourLiftsAndTwoRunsNeedsRecovery() {
        let summaries = (0..<4).map { summary("lift-\($0)", daysAgo: $0) }
            + [
                summary("run-4", daysAgo: 4, source: .strava, kind: .run),
                summary("run-5", daysAgo: 5, source: .strava, kind: .run),
            ]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.sessions, 6)
        XCTAssertEqual(metrics.trainingDays, 6)
        XCTAssertTrue(metrics.needsRecovery)
    }

    /// Endurance alone reaches the threshold too — before #184 six runs read as
    /// zero training days and produced 24 h of suggested rest.
    func testSixRunsOnSixDaysNeedRecovery() {
        let summaries = (0..<6).map { summary("run-\($0)", daysAgo: $0, source: .strava, kind: .run) }

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.sessions, 6)
        XCTAssertEqual(metrics.trainingDays, 6)
        XCTAssertTrue(metrics.needsRecovery)
        XCTAssertEqual(metrics.suggestedRestHours, 48)
    }

    /// A strength-only week is untouched by the change.
    func testAStrengthOnlyWeekIsUnchanged() {
        let summaries = (0..<5).map { summary("lift-\($0)", daysAgo: $0) }

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.sessions, 5)
        XCTAssertEqual(metrics.trainingDays, 5)
        XCTAssertFalse(metrics.needsRecovery)
        XCTAssertEqual(metrics.suggestedRestHours, 24)
        XCTAssertNil(metrics.averageHeartRate)
    }

    /// A run in the morning and a squat session in the evening are one day,
    /// two sessions — the union, not the sum, decides the rule.
    func testADayCarryingBothDomainsCountsOnce() {
        let summaries = [
            summary("lift", daysAgo: 1),
            summary("run", daysAgo: 1, source: .strava, kind: .run),
        ]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.sessions, 2)
        XCTAssertEqual(metrics.trainingDays, 1)
    }

    // MARK: - Heart rate

    /// Mean over the sessions of the week that recorded one; a session without
    /// a strap is skipped rather than counted as zero (US-15 AC7).
    func testAverageHeartRateOverTheSessionsThatRecordedOne() {
        let summaries = [
            summary("lift", daysAgo: 1),
            summary("run", daysAgo: 2, source: .strava, kind: .run, heartRate: 150),
            summary("ride", daysAgo: 3, source: .strava, kind: .ride, heartRate: 140),
            summary("indoor", daysAgo: 4, source: .polar, kind: .run),
            summary("old", daysAgo: 9, source: .strava, kind: .run, heartRate: 200),
        ]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.averageHeartRate, 145)
    }

    /// Rounded half away from zero, so 145.5 reads as 146 rather than 145.
    func testAverageHeartRateIsRounded() {
        let summaries = [
            summary("a", daysAgo: 1, source: .strava, kind: .run, heartRate: 145),
            summary("b", daysAgo: 2, source: .strava, kind: .run, heartRate: 146),
        ]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.averageHeartRate, 146)
    }

    /// A Polar strength session carries a heart rate as well, and the card says
    /// "Avg HR" rather than "average endurance heart rate" — so it counts.
    func testAStrengthSessionThatRecordedAHeartRateCounts() {
        let summaries = [summary("gym", daysAgo: 1, source: .polar, kind: .strength, heartRate: 120)]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.averageHeartRate, 120)
    }

    func testAverageHeartRateIsNilWhenNothingRecordedOne() {
        let summaries = [summary("run", daysAgo: 1, source: .strava, kind: .run)]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertNil(metrics.averageHeartRate)
    }

    // MARK: - Session selection

    /// The RPE is read from the strength sessions only, so `AnalysisViewModel`
    /// fetches those details and no others (#184).
    func testLastSevenDaysStrengthSessionsExcludesEndurance() {
        let summaries = [
            summary("lift", daysAgo: 1),
            summary("run", daysAgo: 2, source: .strava, kind: .run),
            summary("gym", daysAgo: 3, source: .strava, kind: .strength),
            summary("old-lift", daysAgo: 9),
        ]

        let strength = RecoveryMetrics.lastSevenDaysStrengthSessions(
            in: summaries,
            now: reference,
            calendar: calendar
        )
        let all = RecoveryMetrics.lastSevenDaysSessions(in: summaries, now: reference, calendar: calendar)

        XCTAssertEqual(strength.map(\.id).sorted(), ["gym", "lift"])
        XCTAssertEqual(all.map(\.id).sorted(), ["gym", "lift", "run"])
    }

    /// The flip of #183 from the other side: a Strava `WeightTraining` session
    /// is strength work, so it counts towards the recovery figures where
    /// before the source kept it out.
    func testAStravaStrengthSessionIsCounted() {
        let summaries = [
            summary("lift", daysAgo: 1),
            summary("gym", daysAgo: 2, source: .strava, kind: .strength),
        ]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.sessions, 2)
        XCTAssertEqual(metrics.trainingDays, 2)
    }

    /// The mean RPE stays strength-only across the split (#184): Strava's
    /// Relative Effort is a provider-specific score, not a 1-10 RPE, so a week
    /// of runs has no RPE however hard it was.
    func testAverageRPEStaysStrengthOnlyInAMixedWeek() throws {
        let summaries = [
            summary("lift", daysAgo: 1),
            summary("run", daysAgo: 2, source: .strava, kind: .run, heartRate: 150),
        ]
        let details = [
            detail("lift", daysAgo: 1, sets: [set(0, .normal, rpe: 8), set(1, .normal, rpe: 9)]),
        ]

        let metrics = RecoveryMetrics(summaries: summaries, details: details, now: reference, calendar: calendar)

        XCTAssertEqual(try XCTUnwrap(metrics.averageRPE), 8.5, accuracy: 0.0001)
        XCTAssertEqual(metrics.sessions, 2)
        XCTAssertEqual(metrics.averageHeartRate, 150)
    }

    func testAverageRPEIsNilWhenNoRPEWasLogged() {
        let summaries = [summary("w1", daysAgo: 1)]
        let details = [detail("w1", daysAgo: 1, sets: [set(0, .normal, rpe: nil), set(1, .normal, rpe: nil)])]

        let metrics = RecoveryMetrics(summaries: summaries, details: details, now: reference, calendar: calendar)

        XCTAssertNil(metrics.averageRPE)
    }

    /// Mean over counted sets of the last seven days only: warm-ups and older
    /// sessions do not count, and sets without RPE are skipped, not zeros.
    func testAverageRPEOverCountedSetsOfTheLastSevenDays() throws {
        let summaries = [summary("recent", daysAgo: 1), summary("old", daysAgo: 10)]
        let details = [
            detail("recent", daysAgo: 1, sets: [
                set(0, .warmup, rpe: 6),
                set(1, .normal, rpe: 8),
                set(2, .normal, rpe: 9),
                set(3, .normal, rpe: nil),
            ]),
            detail("old", daysAgo: 10, sets: [set(0, .normal, rpe: 10)]),
        ]

        let metrics = RecoveryMetrics(summaries: summaries, details: details, now: reference, calendar: calendar)

        XCTAssertEqual(try XCTUnwrap(metrics.averageRPE), 8.5, accuracy: 0.0001)
    }

    func testRoundTripsThroughJSON() throws {
        let metrics = RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2, averageHeartRate: 148)
        let data = try JSONEncoder().encode(metrics)

        XCTAssertEqual(try JSONDecoder().decode(RecoveryMetrics.self, from: data), metrics)
    }

    /// A report persisted before #184 has no `averageHeartRate` key. It has to
    /// read back without one rather than fail to decode and drop the whole
    /// report to prose (`AnalysisReportFormat`).
    func testDecodesAReportWrittenBeforeTheHeartRateExisted() throws {
        let json = Data(#"{"sessions":6,"trainingDays":6,"averageRPE":8.2,"suggestedRestHours":48}"#.utf8)

        let metrics = try JSONDecoder().decode(RecoveryMetrics.self, from: json)

        XCTAssertNil(metrics.averageHeartRate)
        XCTAssertEqual(metrics, RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2))
    }

    // MARK: - Helpers

    private func start(daysAgo: Int) -> Date {
        calendar.startOfDay(for: reference).addingTimeInterval(Double(-daysAgo) * 86_400 + 43_200)
    }

    private func summary(
        _ id: String,
        daysAgo: Int,
        source: ConnectorSource = .hevy,
        kind: ActivityKind = .strength,
        heartRate: Int? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            title: "Session",
            startTime: start(daysAgo: daysAgo),
            source: source,
            kind: kind,
            volumeKg: kind.isEndurance ? 0 : 1_000,
            exerciseCount: 1,
            countedSetCount: 3,
            distanceMeters: kind.isEndurance ? 8_000 : nil,
            cardio: heartRate.map { CardioMetrics(averageHeartRate: $0) }
        )
    }

    private func detail(_ id: String, daysAgo: Int, sets: [SetDetail]) -> WorkoutDetail {
        WorkoutDetail(
            id: id,
            title: "Session",
            workoutDescription: nil,
            startTime: start(daysAgo: daysAgo),
            endTime: nil,
            volumeKg: 0,
            countedSetCount: 0,
            exercises: [ExerciseDetail(index: 0, title: "Bench Press", sets: sets)]
        )
    }

    private func set(_ index: Int, _ type: SetType, rpe: Double?) -> SetDetail {
        SetDetail(index: index, type: type, weightKg: 60, reps: 5, distanceMeters: nil, durationSeconds: nil, rpe: rpe)
    }
}
