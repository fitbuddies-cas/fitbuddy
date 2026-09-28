import XCTest
@testable import FitBuddy

/// `EffortSeries` and the effort half of `AnalysisReportEvidence` (#246):
/// one series per scale, by week of the window, holding only what was
/// recorded (ADR-014 §4, ADR-015 §1).
final class EffortSeriesTests: XCTestCase {
    /// 10:40 UTC.
    private static let now = Date(timeIntervalSince1970: 1_788_000_000)

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    // MARK: - Buckets

    /// Week 0 is the reference day and the six before it, as everywhere else
    /// in the analysis (`AnalysisWindow.weekStart`).
    func testValuesLandInTheWeekOfTheirDay() {
        let series = build([
            hevy(daysAgo: 0, rpe: 8),
            hevy(daysAgo: 6, rpe: 7),
            hevy(daysAgo: 7, rpe: 6),
            hevy(daysAgo: 27, rpe: 9),
        ])

        XCTAssertEqual(series, [EffortSeries(scale: .hevyRPE, valuesByWeek: [0: [8, 7], 1: [6], 3: [9]])])
    }

    func testSessionsOutsideTheWindowAreIgnored() {
        let series = build([hevy(daysAgo: 28, rpe: 9), hevy(daysAgo: -1, rpe: 9)])

        XCTAssertEqual(series, [])
    }

    func testTheMeansAreOverTheSessionsOfTheirWeeks() {
        let series = EffortSeries(scale: .hevyRPE, valuesByWeek: [0: [8, 9], 1: [6], 3: [7, 7, 7]])

        XCTAssertEqual(series.weeksWithValues, 3)
        XCTAssertEqual(series.lastSevenDaysMean, 8.5)
        XCTAssertEqual(series.precedingWeeksMean, 6.75)
    }

    // MARK: - Source-marked, one series per scale (ADR-015)

    func testEveryScaleIsItsOwnSeries() {
        let series = build([
            hevy(daysAgo: 1, rpe: 8),
            session(.strava, daysAgo: 1, cardio: CardioMetrics(relativeEffort: 80)),
            session(.polar, daysAgo: 2, cardio: CardioMetrics(cardioLoad: 120, muscleLoad: 40, perceivedLoad: 300)),
        ])

        XCTAssertEqual(series, [
            EffortSeries(scale: .hevyRPE, valuesByWeek: [0: [8]]),
            EffortSeries(scale: .stravaRelativeEffort, valuesByWeek: [0: [80]]),
            EffortSeries(scale: .polarCardioLoad, valuesByWeek: [0: [120]]),
            EffortSeries(scale: .polarPerceivedLoad, valuesByWeek: [0: [300]]),
            EffortSeries(scale: .polarMuscleLoad, valuesByWeek: [0: [40]]),
        ])
    }

    /// A scale is its provider's: a field another provider filled is not read
    /// into it.
    func testAScaleReadsOnlyItsOwnProvider() {
        let series = build([
            session(.strava, daysAgo: 1, cardio: CardioMetrics(cardioLoad: 120)),
            session(.polar, daysAgo: 1, cardio: CardioMetrics(relativeEffort: 80)),
        ])

        XCTAssertEqual(series, [])
    }

    /// Polar's `user-rpe` is an enum without numbers (ADR-015 §5), and the
    /// legacy `training_load` has no label in v0 (ADR-015 §2): neither is a
    /// series.
    func testPolarRPEAndTheLegacyTrainingLoadAreNotRead() {
        let series = build([
            session(.polar, daysAgo: 1, cardio: CardioMetrics(trainingLoad: 90, userRPE: .hard)),
        ])

        XCTAssertEqual(series, [])
    }

    // MARK: - No substitute (AC5, ADR-014 §4)

    /// A session without a value is left out — not counted as `0`. Were it a
    /// `0`, the preceding weeks' mean would drop from 5 to 3.3 and the last
    /// seven days' 6 would read as rising instead of stable (120 %).
    func testAMissingValueIsNotAZero() {
        let series = build([
            hevy(daysAgo: 0, rpe: 6),
            hevy(daysAgo: 8, rpe: 5),
            hevy(daysAgo: 9, rpe: nil),
            hevy(daysAgo: 15, rpe: 5),
        ])

        XCTAssertEqual(series, [EffortSeries(scale: .hevyRPE, valuesByWeek: [0: [6], 1: [5], 2: [5]])])
        XCTAssertEqual(series.first.flatMap(AnalysisVerdictRule.trend(of:)), .stable)
    }

    /// A week whose sessions recorded nothing is not a week with a value, so
    /// it does not help a scale qualify.
    func testAWeekWithoutValuesDoesNotCountTowardsQualification() {
        let series = build([
            hevy(daysAgo: 0, rpe: 9),
            hevy(daysAgo: 8, rpe: 6),
            hevy(daysAgo: 15, rpe: nil),
        ])

        XCTAssertEqual(series.first?.weeksWithValues, 2)
        XCTAssertNil(series.first.flatMap(AnalysisVerdictRule.trend(of:)))
    }

    /// A recorded zero is "not measured", as a zero heart rate is.
    func testAZeroIsNotAValue() {
        let series = build([
            session(.strava, daysAgo: 1, cardio: CardioMetrics(relativeEffort: 0)),
            session(.polar, daysAgo: 1, cardio: CardioMetrics(cardioLoad: 0)),
        ])

        XCTAssertEqual(series, [])
    }

    // MARK: - Evidence

    /// The ordinary case: nothing recorded, no series — not an empty series
    /// and not a series of zeros.
    func testEvidenceWithoutEffortDataCarriesNone() {
        let evidence = evidence([hevy(daysAgo: 1, rpe: nil), session(.strava, daysAgo: 2, cardio: nil)])

        XCTAssertEqual(evidence.effort, [])
    }

    /// The evidence holds the scales the profile reads, over the sessions it
    /// covers.
    func testEvidenceHoldsTheScalesOfItsProfile() {
        let sessions = [
            hevy(daysAgo: 1, rpe: 8),
            session(.strava, daysAgo: 1, cardio: CardioMetrics(relativeEffort: 80)),
        ]

        XCTAssertEqual(evidence(sessions, analysisProfile: .strength).effort.map(\.scale), [.hevyRPE])
        XCTAssertEqual(evidence(sessions, analysisProfile: .endurance).effort.map(\.scale), [.stravaRelativeEffort])
        XCTAssertEqual(
            evidence(sessions, analysisProfile: .overallLoad).effort.map(\.scale),
            [.hevyRPE, .stravaRelativeEffort]
        )
    }

    // MARK: - The Hevy value per session

    /// One value per session: the mean over the counted sets that logged an
    /// RPE. Warm-ups and sets without one stay out.
    func testASessionsRPEIsTheMeanOfItsCountedSets() {
        let workout = Workout(
            id: "workout",
            title: "Session",
            startTime: Self.now,
            exercises: [Exercise(index: 0, title: "Bench Press (Barbell)", sets: [
                ExerciseSet(index: 0, type: .warmup, weightKg: 40, reps: 10, rpe: 5),
                ExerciseSet(index: 1, type: .normal, weightKg: 60, reps: 5, rpe: 7),
                ExerciseSet(index: 2, type: .normal, weightKg: 60, reps: 5, rpe: 9),
                ExerciseSet(index: 3, type: .normal, weightKg: 60, reps: 5),
            ])]
        )

        XCTAssertEqual(WorkoutSummary(workout: workout).averageRPE, 8)
    }

    func testASessionWithoutRPEHasNone() {
        let workout = Workout(
            id: "workout",
            title: "Session",
            startTime: Self.now,
            exercises: [Exercise(index: 0, title: "Bench Press (Barbell)", sets: [
                ExerciseSet(index: 0, type: .normal, weightKg: 60, reps: 5),
            ])]
        )

        XCTAssertNil(WorkoutSummary(workout: workout).averageRPE)
    }

    // MARK: - Fixtures

    private func build(_ sessions: [WorkoutSummary]) -> [EffortSeries] {
        EffortSeries.series(in: sessions, window: .default, now: Self.now, calendar: Self.calendar)
    }

    private func evidence(
        _ sessions: [WorkoutSummary],
        analysisProfile: AnalysisProfile = .overallLoad
    ) -> AnalysisReportEvidence {
        AnalysisReportEvidence(
            summaries: sessions,
            exercises: [],
            progressions: [:],
            details: [],
            window: .default,
            now: Self.now,
            calendar: Self.calendar,
            analysisProfile: analysisProfile
        )
    }

    private func hevy(daysAgo: Int, rpe: Double?) -> WorkoutSummary {
        WorkoutSummary(
            id: "hevy-\(daysAgo)",
            title: "Push",
            startTime: date(daysAgo: daysAgo),
            volumeKg: 1_000,
            exerciseCount: 1,
            countedSetCount: 3,
            averageRPE: rpe
        )
    }

    private func session(_ source: ConnectorSource, daysAgo: Int, cardio: CardioMetrics?) -> WorkoutSummary {
        WorkoutSummary(
            id: "\(source.rawValue)-\(daysAgo)",
            title: "Ride",
            startTime: date(daysAgo: daysAgo),
            source: source,
            kind: .ride,
            volumeKg: 0,
            exerciseCount: 0,
            countedSetCount: 0,
            durationSeconds: 3_600,
            cardio: cardio
        )
    }

    private func date(daysAgo: Int) -> Date {
        Self.now.addingTimeInterval(-Double(daysAgo) * 86_400)
    }
}
