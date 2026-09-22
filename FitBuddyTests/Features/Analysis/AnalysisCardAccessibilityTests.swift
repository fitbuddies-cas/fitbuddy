import XCTest
@testable import FitBuddy

/// The VoiceOver sentence of each report card (#177).
final class AnalysisCardAccessibilityTests: XCTestCase {
    func testProgressionSaysWhichWayTheWeightMoves() {
        let label = AnalysisCardAccessibility.label(
            for: .progression(
                exercise: "Bench Press (Barbell)",
                muscleGroup: .chest,
                fromKg: 60,
                toKg: 62.5,
                reasoning: "Reps held."
            )
        )

        XCTAssertEqual(label, "Increase. Bench Press (Barbell), Chest. From 60 kg to 62.5 kg, +2.5 kg. Reps held.")
    }

    /// The heart rate is spoken out, so VoiceOver does not spell "HR" (#184).
    func testRecoveryReadsTheHeartRateOfAMixedWeek() {
        let label = AnalysisCardAccessibility.label(
            for: .recovery(
                reasoning: "Rest.",
                metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2, averageHeartRate: 148)
            )
        )

        XCTAssertEqual(
            label,
            """
            Recovery. You trained 6 of the last 7 days. Rest. 6 sessions in the last 7 days, \
            average RPE 8.2, average heart rate 148 beats per minute, suggested rest 48 hours.
            """
        )
    }

    func testRecoveryReadsItsFiguresAndSkipsAMissingRPE() {
        let withRPE = AnalysisCardAccessibility.label(
            for: .recovery(reasoning: "Rest.", metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.2))
        )
        let withoutRPE = AnalysisCardAccessibility.label(
            for: .recovery(reasoning: "Rest.", metrics: RecoveryMetrics(sessions: 7, trainingDays: 7, averageRPE: nil))
        )

        XCTAssertEqual(
            withRPE,
            """
            Recovery. You trained 6 of the last 7 days. Rest. 6 sessions in the last 7 days, \
            average RPE 8.2, suggested rest 48 hours.
            """
        )
        XCTAssertFalse(withoutRPE.contains("RPE"))
        XCTAssertTrue(withoutRPE.contains("suggested rest 72 hours"))
    }

    func testImbalanceSpellsOutTheFrequencies() {
        let label = AnalysisCardAccessibility.label(
            for: .imbalance(groupA: .legs, perWeekA: 1, groupB: .chest, perWeekB: 3, reasoning: "Add legs.")
        )

        XCTAssertEqual(label, "Imbalance. Chest 3 times per week, Legs 1 time per week. Add legs.")
    }

    func testNoteReadsTitleThenText() {
        XCTAssertEqual(
            AnalysisCardAccessibility.label(for: .note(title: "Rows", text: "Add a rep.")),
            "Rows. Add a rep."
        )
    }
}
