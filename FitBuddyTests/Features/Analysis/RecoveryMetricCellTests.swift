import XCTest
@testable import FitBuddy

/// The recovery card's metrics row (US-14 AC4, #177).
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
}
