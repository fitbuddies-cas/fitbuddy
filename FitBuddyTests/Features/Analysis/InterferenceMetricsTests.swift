import XCTest
@testable import FitBuddy

/// `InterferenceMetrics` (#186): how strength and endurance sat in the same
/// seven days, counted by the app (US-15 AC2).
final class InterferenceMetricsTests: XCTestCase {
    private var calendar: Calendar!
    /// 2025-06-15 12:26:40 UTC.
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    }

    /// The card's own scenario: four lifting days, four running days, three of
    /// them the same day.
    func testCountsTheDaysEachDomainFilledAndTheDaysTheyShared() {
        let summaries = [
            summary("lift-0", daysAgo: 0),
            summary("lift-1", daysAgo: 1),
            summary("lift-2", daysAgo: 2),
            summary("lift-4", daysAgo: 4),
            run("run-0", daysAgo: 0),
            run("run-1", daysAgo: 1),
            run("run-2", daysAgo: 2),
            run("run-5", daysAgo: 5),
        ]

        let metrics = InterferenceMetrics.metrics(in: summaries, now: reference, calendar: calendar)

        XCTAssertEqual(metrics.strengthDays, 4)
        XCTAssertEqual(metrics.cardioDays, 4)
        XCTAssertEqual(metrics.overlapDays, 3)
        XCTAssertEqual(metrics.days, 7)
        XCTAssertTrue(metrics.hasBothDomains)
    }

    /// Two sessions of the same domain on one day are one day — the reason the
    /// card counts days rather than sessions.
    func testTwoSessionsOnOneDayAreOneDay() {
        let summaries = [
            summary("morning", daysAgo: 1),
            summary("evening", daysAgo: 1),
            run("run", daysAgo: 3),
        ]

        let metrics = InterferenceMetrics.metrics(in: summaries, now: reference, calendar: calendar)

        XCTAssertEqual(metrics.strengthDays, 1)
        XCTAssertEqual(metrics.cardioDays, 1)
        XCTAssertEqual(metrics.overlapDays, 0)
    }

    /// The week is the same seven days `RecoveryMetrics` judges, so a report
    /// cannot cite two different weeks.
    func testSessionsOlderThanSevenDaysDoNotCount() {
        let summaries = [summary("lift", daysAgo: 1), run("run", daysAgo: 7)]

        let metrics = InterferenceMetrics.metrics(in: summaries, now: reference, calendar: calendar)

        XCTAssertEqual(metrics.strengthDays, 1)
        XCTAssertEqual(metrics.cardioDays, 0)
        XCTAssertFalse(metrics.hasBothDomains)
    }

    /// The domain is the sport, not the source (ADR-012): a Strava
    /// `WeightTraining` session is a strength day, a Hevy treadmill session a
    /// cardio one.
    func testTheSportDecidesTheDomainNotTheSource() {
        let summaries = [
            WorkoutSummary(
                id: "strava-lift",
                title: "Gym",
                startTime: start(daysAgo: 1),
                source: .strava,
                kind: .strength,
                volumeKg: 2_000,
                exerciseCount: 3,
                countedSetCount: 9
            ),
            WorkoutSummary(
                id: "hevy-treadmill",
                title: "Treadmill",
                startTime: start(daysAgo: 2),
                source: .hevy,
                kind: .strength,
                volumeKg: 0,
                exerciseCount: 1,
                countedSetCount: 1,
                distanceMeters: 6_000
            ),
        ]

        let metrics = InterferenceMetrics.metrics(in: summaries, now: reference, calendar: calendar)

        XCTAssertEqual(metrics.strengthDays, 1)
        XCTAssertEqual(metrics.cardioDays, 1)
        XCTAssertTrue(metrics.hasBothDomains)
    }

    /// A week of one domain has no interference to write about, whatever a
    /// card claims — which is what the validator turns such a card into a note
    /// on.
    func testASingleDomainWeekHasNoInterference() {
        let metrics = InterferenceMetrics.metrics(
            in: [summary("lift", daysAgo: 1), summary("lift-2", daysAgo: 3)],
            now: reference,
            calendar: calendar
        )

        XCTAssertEqual(metrics.strengthDays, 2)
        XCTAssertEqual(metrics.cardioDays, 0)
        XCTAssertEqual(metrics.overlapDays, 0)
        XCTAssertFalse(metrics.hasBothDomains)
    }

    /// A stored card keeps the week it was written for (#176).
    func testTheFiguresSurviveARoundTrip() throws {
        let metrics = InterferenceMetrics(strengthDays: 4, cardioDays: 3, overlapDays: 2)

        let decoded = try JSONDecoder().decode(
            InterferenceMetrics.self,
            from: JSONEncoder().encode(metrics)
        )

        XCTAssertEqual(decoded, metrics)
    }

    // MARK: - Fixtures

    private func start(daysAgo: Int) -> Date {
        calendar.startOfDay(for: reference).addingTimeInterval(Double(-daysAgo) * 86_400 + 43_200)
    }

    private func summary(_ id: String, daysAgo: Int) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            title: "Session",
            startTime: start(daysAgo: daysAgo),
            source: .hevy,
            kind: .strength,
            volumeKg: 1_000,
            exerciseCount: 1,
            countedSetCount: 3
        )
    }

    private func run(_ id: String, daysAgo: Int) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            title: "Run",
            startTime: start(daysAgo: daysAgo),
            source: .strava,
            kind: .run,
            volumeKg: 0,
            exerciseCount: 0,
            countedSetCount: 0,
            distanceMeters: 8_000,
            durationSeconds: 2_400
        )
    }
}
