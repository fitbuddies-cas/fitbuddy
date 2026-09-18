import XCTest
@testable import FitBuddy

/// The recovery card's metrics row (US-14 AC4, US-15 AC7, #177, #184).
final class RecoveryMetricCellTests: XCTestCase {
    func testAllThreeCellsWithAnRPE() {
        let cells = RecoveryMetricCell.cells(
            for: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2)
        )

        XCTAssertEqual(cells, [
            RecoveryMetricCell(label: "Sessions / 7d", value: "6"),
            RecoveryMetricCell(label: "Avg RPE", value: "8.2"),
            RecoveryMetricCell(label: "Suggested rest", value: "48 h"),
        ])
    }

    /// No RPE logged: the cell is gone, not a "—".
    func testTheRPECellIsDroppedWithoutAnRPE() {
        let cells = RecoveryMetricCell.cells(
            for: RecoveryMetrics(sessions: 7, trainingDays: 7, averageRPE: nil)
        )

        XCTAssertEqual(cells.map(\.label), ["Sessions / 7d", "Suggested rest"])
        XCTAssertEqual(cells.map(\.value), ["7", "72 h"])
        XCTAssertFalse(cells.contains { $0.value == "—" })
    }

    /// A mixed week that logged both means: four cells, RPE before heart rate
    /// (#184).
    func testAMixedWeekShowsFourCells() {
        let cells = RecoveryMetricCell.cells(
            for: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2, averageHeartRate: 148)
        )

        XCTAssertEqual(cells, [
            RecoveryMetricCell(label: "Sessions / 7d", value: "6"),
            RecoveryMetricCell(label: "Avg RPE", value: "8.2"),
            RecoveryMetricCell(label: "Avg HR", value: "148", unit: "bpm"),
            RecoveryMetricCell(label: "Suggested rest", value: "48 h"),
        ])
    }

    /// Six runs: nothing logged an RPE, the strap recorded a heart rate. Three
    /// cells, and no placeholder where the RPE would have been (US-15 AC7).
    func testAnEnduranceOnlyWeekShowsTheHeartRateAndNoRPE() {
        let cells = RecoveryMetricCell.cells(
            for: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil, averageHeartRate: 151)
        )

        XCTAssertEqual(cells.map(\.label), ["Sessions / 7d", "Avg HR", "Suggested rest"])
        XCTAssertEqual(cells.map(\.value), ["6", "151", "48 h"])
        XCTAssertEqual(cells.map(\.unit), [nil, "bpm", nil])
        XCTAssertFalse(cells.contains { $0.value == "—" })
    }

    /// A Hevy-only week is what it was before #184: no heart rate anywhere,
    /// so no cell for one.
    func testAStrengthOnlyWeekKeepsItsThreeCells() {
        let cells = RecoveryMetricCell.cells(
            for: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2)
        )

        XCTAssertEqual(cells.map(\.label), ["Sessions / 7d", "Avg RPE", "Suggested rest"])
    }
}
