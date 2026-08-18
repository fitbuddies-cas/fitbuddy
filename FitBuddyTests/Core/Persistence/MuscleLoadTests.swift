import XCTest
@testable import FitBuddy

final class MuscleLoadTests: XCTestCase {
    func testMergesLoadsOfTheSameGroup() {
        let merged = MuscleLoad.merged([
            MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3),
            MuscleLoad(group: .chest, volumeKg: 500, setCount: 2),
            MuscleLoad(group: .legs, volumeKg: 2_000, setCount: 4),
        ])

        XCTAssertEqual(merged, [
            MuscleLoad(group: .legs, volumeKg: 2_000, setCount: 4),
            MuscleLoad(group: .chest, volumeKg: 1_500, setCount: 5),
        ])
    }

    func testSortsHeaviestFirst() {
        let merged = MuscleLoad.merged([
            MuscleLoad(group: .arms, volumeKg: 300, setCount: 2),
            MuscleLoad(group: .back, volumeKg: 900, setCount: 5),
            MuscleLoad(group: .legs, volumeKg: 600, setCount: 4),
        ])

        XCTAssertEqual(merged.map(\.group), [.back, .legs, .arms])
    }

    /// Bodyweight and cardio work produces no kg volume — the group still has
    /// to reach the chart, otherwise a pull-up-only back disappears from it.
    func testKeepsGroupsWithoutVolume() {
        let merged = MuscleLoad.merged([
            MuscleLoad(group: .core, volumeKg: 0, setCount: 6),
            MuscleLoad(group: .chest, volumeKg: 800, setCount: 3),
        ])

        XCTAssertEqual(merged.map(\.group), [.chest, .core])
        XCTAssertEqual(merged.last?.setCount, 6)
    }

    /// Equal volumes must not reshuffle between two reads of the same cache.
    func testTiesKeepAStableOrder() {
        let loads = [
            MuscleLoad(group: .arms, volumeKg: 500, setCount: 2),
            MuscleLoad(group: .chest, volumeKg: 500, setCount: 2),
            MuscleLoad(group: .legs, volumeKg: 500, setCount: 2),
        ]

        XCTAssertEqual(MuscleLoad.merged(loads).map(\.group), [.chest, .legs, .arms])
        XCTAssertEqual(MuscleLoad.merged(loads.reversed()).map(\.group), [.chest, .legs, .arms])
    }

    /// An exercise made up of warm-up sets contributes neither volume nor
    /// counted sets — its group must not show up as an empty row.
    func testGroupsWithoutCountedSetsAreDropped() {
        let merged = MuscleLoad.merged([
            MuscleLoad(group: .shoulders, volumeKg: 0, setCount: 0),
            MuscleLoad(group: .chest, volumeKg: 800, setCount: 3),
        ])

        XCTAssertEqual(merged.map(\.group), [.chest])
    }

    func testEmptyInputProducesNoBars() {
        XCTAssertTrue(MuscleLoad.merged([]).isEmpty)
    }
}
