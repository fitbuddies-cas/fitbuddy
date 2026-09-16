import XCTest
@testable import FitBuddy

/// The figures and derived sentences of the report cards (#177).
final class AnalysisCardFormatterTests: XCTestCase {
    // MARK: - Weight

    func testWeightsDropTrailingZeros() {
        XCTAssertEqual(AnalysisCardFormatter.weight(60), "60 kg")
        XCTAssertEqual(AnalysisCardFormatter.weight(62.5), "62.5 kg")
    }

    /// A 1.25 kg plate step must not print as a weight nobody can load.
    func testQuarterKilogramsSurvive() {
        XCTAssertEqual(AnalysisCardFormatter.weight(61.25), "61.25 kg")
    }

    // MARK: - Delta

    func testDeltaIsSignedAndInKilograms() {
        XCTAssertEqual(AnalysisCardFormatter.delta(fromKg: 60, toKg: 62.5), "+2.5 kg")
        XCTAssertEqual(AnalysisCardFormatter.delta(fromKg: 80, toKg: 85), "+5 kg")
        XCTAssertEqual(AnalysisCardFormatter.delta(fromKg: 8.75, toKg: 10), "+1.25 kg")
    }

    func testANegativeDeltaUsesAMinusSign() {
        XCTAssertEqual(AnalysisCardFormatter.delta(fromKg: 62.5, toKg: 60), "\u{2212}2.5 kg")
    }

    /// `62.5 - 60.1` is `2.3999…` in binary floating point.
    func testFloatingPointNoiseIsRoundedAway() {
        XCTAssertEqual(AnalysisCardFormatter.delta(fromKg: 60.1, toKg: 62.5), "+2.4 kg")
    }

    // MARK: - Imbalance

    func testPerWeekIsWrittenAsThePromptWritesIt() {
        XCTAssertEqual(AnalysisCardFormatter.perWeek(3), "3×/wk")
        XCTAssertEqual(AnalysisCardFormatter.perWeek(0.8), "0.8×/wk")
        XCTAssertEqual(AnalysisCardFormatter.perWeek(2.5), "2.5×/wk")
    }

    func testImbalanceTitleAndHeadlineFollowTheBarOrder() {
        let bars = ImbalanceBar.bars(groupA: .legs, perWeekA: 1, groupB: .chest, perWeekB: 3)
        XCTAssertEqual(AnalysisCardFormatter.imbalanceTitle(bars), "Chest vs Legs")
        XCTAssertEqual(
            AnalysisCardFormatter.imbalanceHeadline(bars),
            "You're training chest 3×/week but legs only 1×/week."
        )
    }

    // MARK: - Recovery

    func testRecoveryHeadlineNamesTheTrainingDays() {
        let metrics = RecoveryMetrics(sessions: 7, trainingDays: 6, averageRPE: nil)
        XCTAssertEqual(AnalysisCardFormatter.recoveryHeadline(metrics), "You trained 6 of the last 7 days.")
    }

    func testRPEHasOneDecimalAndRestIsInHours() {
        XCTAssertEqual(AnalysisCardFormatter.rpe(8.2), "8.2")
        XCTAssertEqual(AnalysisCardFormatter.rpe(8), "8.0")
        XCTAssertEqual(AnalysisCardFormatter.rest(hours: 48), "48 h")
    }
}
