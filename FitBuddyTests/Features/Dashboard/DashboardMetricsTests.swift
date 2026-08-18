import XCTest
@testable import FitBuddy

/// Unit tests for the dashboard aggregates of US-2 AC1.
final class DashboardMetricsTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)
    /// UTC so the day boundaries in these tests do not depend on the machine.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // Test fixture: "UTC" is a valid identifier.
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    func testTotalVolumeSumsEveryWorkout() {
        let metrics = DashboardMetrics(
            summaries: [
                summary(id: "a", daysAgo: 1, volume: 1200),
                summary(id: "b", daysAgo: 3, volume: 800.5),
            ],
            calendar: calendar
        )

        XCTAssertEqual(metrics.totalVolumeKg, 2000.5, accuracy: 0.001)
        XCTAssertEqual(metrics.workoutCount, 2)
    }

    func testTwoWorkoutsOnTheSameDayCountAsOneTrainingDay() {
        let metrics = DashboardMetrics(
            summaries: [
                summary(id: "morning", daysAgo: 2, volume: 500),
                summary(id: "evening", daysAgo: 2, hourOfDay: 19, volume: 500),
                summary(id: "other-day", daysAgo: 5, volume: 500),
            ],
            calendar: calendar
        )

        XCTAssertEqual(metrics.workoutCount, 3)
        XCTAssertEqual(metrics.trainingDayCount, 2)
    }

    func testAverageTrainingDaysPerWeekSpreadsOverTheFullWindow() {
        // 39 training days across the window, every other day.
        let summaries = (0..<39).map { summary(id: "w-\($0)", daysAgo: $0 * 2, volume: 100) }

        let metrics = DashboardMetrics(summaries: summaries, calendar: calendar)

        XCTAssertEqual(metrics.trainingDayCount, 39)
        XCTAssertEqual(metrics.averageTrainingDaysPerWeek, 39 / 13.0, accuracy: 0.001)
        XCTAssertEqual(metrics.averageTrainingDaysPerWeek, 3, accuracy: 0.001)
    }

    /// Training on every single day of the window must not produce a figure
    /// above 7 — the divisor has to cover both boundary days.
    func testTrainingEveryDayOfTheWindowStaysAtSevenPerWeek() {
        let summaries = (0..<TrainingWindow.spanDays).map {
            summary(id: "w-\($0)", daysAgo: $0, volume: 100)
        }

        let metrics = DashboardMetrics(summaries: summaries, calendar: calendar)

        XCTAssertEqual(metrics.trainingDayCount, 91)
        XCTAssertEqual(metrics.averageTrainingDaysPerWeek, 7, accuracy: 0.001)
    }

    func testEmptyWindowIsAllZeros() {
        let metrics = DashboardMetrics(summaries: [], calendar: calendar)

        XCTAssertEqual(metrics.totalVolumeKg, 0)
        XCTAssertEqual(metrics.workoutCount, 0)
        XCTAssertEqual(metrics.trainingDayCount, 0)
        XCTAssertEqual(metrics.averageTrainingDaysPerWeek, 0)
    }

    // MARK: - Muscle distribution (#27)

    func testMuscleDistributionAggregatesEveryWorkoutHeaviestFirst() {
        let metrics = DashboardMetrics(
            summaries: [
                summary(id: "push", daysAgo: 1, volume: 1_800, loads: [
                    MuscleLoad(group: .chest, volumeKg: 1_200, setCount: 6),
                    MuscleLoad(group: .arms, volumeKg: 600, setCount: 4),
                ]),
                summary(id: "legs", daysAgo: 3, volume: 2_000, loads: [
                    MuscleLoad(group: .legs, volumeKg: 2_000, setCount: 8),
                ]),
                summary(id: "push-2", daysAgo: 5, volume: 900, loads: [
                    MuscleLoad(group: .chest, volumeKg: 900, setCount: 5),
                ]),
            ],
            calendar: calendar
        )

        XCTAssertEqual(metrics.muscleDistribution, [
            MuscleLoad(group: .chest, volumeKg: 2_100, setCount: 11),
            MuscleLoad(group: .legs, volumeKg: 2_000, setCount: 8),
            MuscleLoad(group: .arms, volumeKg: 600, setCount: 4),
        ])
    }

    /// The chart's bars have to add up to the headline figure — a split that
    /// disagrees with the total would make one of the two wrong.
    func testMuscleDistributionSumsToTheTotalVolume() {
        let metrics = DashboardMetrics(
            summaries: [
                summary(id: "a", daysAgo: 1, volume: 1_800, loads: [
                    MuscleLoad(group: .chest, volumeKg: 1_200, setCount: 6),
                    MuscleLoad(group: .arms, volumeKg: 600, setCount: 4),
                ]),
                summary(id: "b", daysAgo: 2, volume: 2_000, loads: [
                    MuscleLoad(group: .legs, volumeKg: 2_000, setCount: 8),
                ]),
            ],
            calendar: calendar
        )

        let distributed = metrics.muscleDistribution.reduce(0) { $0 + $1.volumeKg }
        XCTAssertEqual(distributed, metrics.totalVolumeKg, accuracy: 0.001)
    }

    func testEmptyWindowHasNoMuscleDistribution() {
        XCTAssertTrue(DashboardMetrics.empty.muscleDistribution.isEmpty)
    }

    // MARK: - Helpers

    private func summary(
        id: String,
        daysAgo: Int,
        hourOfDay: Int = 8,
        volume: Double,
        loads: [MuscleLoad] = []
    ) -> WorkoutSummary {
        let day = calendar.startOfDay(for: reference.addingTimeInterval(Double(-daysAgo) * 86_400))
        let start = day.addingTimeInterval(Double(hourOfDay) * 3600)
        return WorkoutSummary(
            id: id,
            title: "Session",
            startTime: start,
            volumeKg: volume,
            exerciseCount: 4,
            countedSetCount: 12,
            muscleLoads: loads
        )
    }
}
