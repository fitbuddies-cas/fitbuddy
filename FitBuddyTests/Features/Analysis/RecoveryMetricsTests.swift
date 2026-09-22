import XCTest
@testable import FitBuddy

/// `RecoveryMetrics` (#175): the last seven days as the app counts them, and
/// the rest rule.
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

    /// The recovery figures are the strength ones (#144), and "strength" is
    /// the normalized sport since #183: a run is not counted, whichever source
    /// it came from. Counting endurance sessions towards recovery is #184.
    func testEnduranceSessionsAreNotCounted() {
        let summaries = [
            summary("lift", daysAgo: 1),
            summary("run", daysAgo: 2, source: .strava, kind: .run),
        ]

        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.sessions, 1)
        XCTAssertEqual(metrics.trainingDays, 1)
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
        let metrics = RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2)
        let data = try JSONEncoder().encode(metrics)

        XCTAssertEqual(try JSONDecoder().decode(RecoveryMetrics.self, from: data), metrics)
    }

    // MARK: - Helpers

    private func start(daysAgo: Int) -> Date {
        calendar.startOfDay(for: reference).addingTimeInterval(Double(-daysAgo) * 86_400 + 43_200)
    }

    private func summary(
        _ id: String,
        daysAgo: Int,
        source: ConnectorSource = .hevy,
        kind: ActivityKind = .strength
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
            distanceMeters: kind.isEndurance ? 8_000 : nil
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
