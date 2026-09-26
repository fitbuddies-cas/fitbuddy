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

    /// The weight that stays is spoken with the reps, so the sentence says
    /// what moves and what does not (#234).
    func testRepProgressionSaysTheRepsMoveAndTheWeightStays() {
        let label = AnalysisCardAccessibility.label(
            for: .repProgression(
                exercise: "Lateral Raise (Dumbbell)",
                muscleGroup: .shoulders,
                weightKg: 10,
                fromReps: 12,
                toReps: 14,
                reasoning: "Earn the next dumbbell with reps."
            )
        )

        XCTAssertEqual(
            label,
            "More reps. Lateral Raise (Dumbbell), Shoulders. From 12 reps to 14 reps at 10 kg, +2 reps. Earn the next dumbbell with reps."
        )
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

    /// Every unit is spelled out — VoiceOver reads "km" and "bpm" letter by
    /// letter — and the direction is a word, because "32 35" says nothing
    /// about which way the figure moves (#186).
    func testAMetricCardSpellsOutItsUnitAndItsDirection() {
        let label = AnalysisCardAccessibility.label(
            for: .metric(
                label: "Weekly distance",
                from: 32,
                to: 35,
                unit: .kilometers,
                reasoning: "Held for three weeks.",
                source: "Run"
            )
        )

        XCTAssertEqual(
            label,
            "Increase. Run. Weekly distance. From 32 kilometres to 35 kilometres. Held for three weeks."
        )
    }

    /// A card without a source label says nothing in its place (US-15 AC7),
    /// and a lower-is-better unit gets its own word for the same direction.
    func testAPaceCardWithoutASourceReadsAsFaster() {
        let label = AnalysisCardAccessibility.label(
            for: .metric(
                label: "Easy pace",
                from: 6,
                to: 5 + 40.0 / 60,
                unit: .minutesPerKilometer,
                reasoning: "Hold them slower.",
                source: "  "
            )
        )

        XCTAssertEqual(
            label,
            """
            Faster. Easy pace. From 6:00 minutes per kilometre to 5:40 minutes per kilometre. \
            Hold them slower.
            """
        )
    }

    func testAnInterferenceCardReadsItsThreeCounts() {
        let label = AnalysisCardAccessibility.label(
            for: .interference(
                metrics: InterferenceMetrics(strengthDays: 4, cardioDays: 4, overlapDays: 3),
                reasoning: "Move one run."
            )
        )

        XCTAssertEqual(
            label,
            """
            Interference. Strength and endurance shared 3 of the last 7 days. \
            4 strength days, 4 endurance days, 3 days with both, of the last 7. Move one run.
            """
        )
    }

    func testNoteReadsTitleThenText() {
        XCTAssertEqual(
            AnalysisCardAccessibility.label(for: .note(title: "Rows", text: "Add a rep.")),
            "Rows. Add a rep."
        )
    }
}
