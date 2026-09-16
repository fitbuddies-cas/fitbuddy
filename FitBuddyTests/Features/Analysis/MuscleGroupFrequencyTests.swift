import XCTest
@testable import FitBuddy

/// `MuscleGroupFrequency` (#175): sessions per week per muscle group, the
/// figure the prompt states and an imbalance card has to match.
final class MuscleGroupFrequencyTests: XCTestCase {
    func testCountsASessionOncePerGroup() {
        let sessions = [
            session([MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3), MuscleLoad(group: .chest, volumeKg: 500, setCount: 3)]),
            session([MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3), MuscleLoad(group: .legs, volumeKg: 2_000, setCount: 4)]),
        ]

        XCTAssertEqual(MuscleGroupFrequency.sessionCounts(in: sessions), [.chest: 2, .legs: 1])
    }

    func testGroupWithoutCountedSetsIsNotTrained() {
        let sessions = [session([MuscleLoad(group: .back, volumeKg: 0, setCount: 0)])]

        XCTAssertEqual(MuscleGroupFrequency.sessionCounts(in: sessions), [:])
    }

    /// Divided by the window's full length and rounded half away from zero to
    /// one decimal: 3 sessions in 4 weeks is 0.75, written 0.8.
    func testPerWeekIsDividedByTheWindowAndRoundedToOneDecimal() {
        let chest = MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3)
        let legs = MuscleLoad(group: .legs, volumeKg: 1_000, setCount: 3)
        let sessions = Array(repeating: session([chest]), count: 12) + Array(repeating: session([legs]), count: 3)

        let perWeek = MuscleGroupFrequency.sessionsPerWeek(in: sessions, window: .default)

        XCTAssertEqual(perWeek[.chest], 3)
        XCTAssertEqual(perWeek[.legs], 0.8)
        XCTAssertEqual(MuscleGroupFrequency.string(0.8), "0.8")
        XCTAssertEqual(MuscleGroupFrequency.string(3), "3")
    }

    private func session(_ loads: [MuscleLoad]) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID().uuidString,
            title: "Session",
            startTime: Date(timeIntervalSince1970: 1_750_000_000),
            volumeKg: loads.reduce(0) { $0 + $1.volumeKg },
            exerciseCount: loads.count,
            countedSetCount: loads.reduce(0) { $0 + $1.setCount },
            muscleLoads: loads
        )
    }
}
