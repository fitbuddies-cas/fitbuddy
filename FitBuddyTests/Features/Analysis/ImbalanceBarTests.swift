import XCTest
@testable import FitBuddy

/// The imbalance card's bar lengths and order (#177).
final class ImbalanceBarTests: XCTestCase {
    func testTheMoreFrequentGroupFillsItsBar() {
        let bars = ImbalanceBar.bars(groupA: .chest, perWeekA: 3, groupB: .legs, perWeekB: 1)

        XCTAssertEqual(bars.map(\.group), [.chest, .legs])
        XCTAssertEqual(bars[0].share, 1)
        XCTAssertEqual(bars[1].share, 1.0 / 3, accuracy: 1e-9)
    }

    /// The model may name the rarer group first; the full bar still leads.
    func testBarsAreOrderedByFrequency() {
        let bars = ImbalanceBar.bars(groupA: .back, perWeekA: 0.8, groupB: .chest, perWeekB: 2)

        XCTAssertEqual(bars.map(\.group), [.chest, .back])
        XCTAssertEqual(bars.map(\.perWeek), [2, 0.8])
        XCTAssertEqual(bars[1].share, 0.4, accuracy: 1e-9)
    }

    func testATieKeepsTheModelsOrder() {
        let bars = ImbalanceBar.bars(groupA: .arms, perWeekA: 2, groupB: .core, perWeekB: 2)

        XCTAssertEqual(bars.map(\.group), [.arms, .core])
        XCTAssertEqual(bars.map(\.share), [1, 1])
    }

    /// A group never trained reads as an empty bar; two of them do not divide
    /// by zero.
    func testZeroFrequenciesGiveEmptyBars() {
        XCTAssertEqual(
            ImbalanceBar.bars(groupA: .chest, perWeekA: 2, groupB: .legs, perWeekB: 0).map(\.share),
            [1, 0]
        )
        XCTAssertEqual(
            ImbalanceBar.bars(groupA: .chest, perWeekA: 0, groupB: .legs, perWeekB: 0).map(\.share),
            [0, 0]
        )
    }
}
