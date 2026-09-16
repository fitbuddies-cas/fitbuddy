import XCTest
@testable import FitBuddy

/// Wire format of `AnalysisReportCard` and `ValidatedAnalysisReport` (#175),
/// the shape #176 persists.
final class AnalysisReportCardTests: XCTestCase {
    func testEveryCardKindRoundTripsThroughJSON() throws {
        let report = ValidatedAnalysisReport(
            headline: "Recover this week.",
            verdict: .recover,
            lead: "Rest two days first.",
            cards: [
                .recovery(
                    reasoning: "Rest first.",
                    metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil)
                ),
                .progression(exercise: "Bench Press", muscleGroup: .chest, fromKg: 60, toKg: 62.5, reasoning: "Clean."),
                .imbalance(groupA: .chest, perWeekA: 3, groupB: .legs, perWeekB: 0.8, reasoning: "Add legs."),
                .note(title: "Pull-ups", text: "Add a rep."),
            ],
            summary: "Rest, then bench 62.5 kg."
        )

        let data = try JSONEncoder().encode(report)

        XCTAssertEqual(try JSONDecoder().decode(ValidatedAnalysisReport.self, from: data), report)
    }

    func testCardIsAFlatObjectWithKind() throws {
        let card = AnalysisReportCard.progression(
            exercise: "Bench Press", muscleGroup: .chest, fromKg: 60, toKg: 62.5, reasoning: "Clean."
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any]
        )

        XCTAssertEqual(object["kind"] as? String, "progression")
        XCTAssertEqual(object["muscleGroup"] as? String, "chest")
        XCTAssertEqual(object["fromKg"] as? Double, 60)
    }

    // MARK: - Stored rows (#179)

    // Decoded from literal JSON, as a row written by an earlier build holds
    // it. A round trip alone would pass after a renamed key too, and every
    // report already in the history would then fall back to prose.

    func testDecodesAStoredProgressionCard() throws {
        let card = try decode("""
        {"kind": "progression", "exercise": "Bench Press (Barbell)", "muscleGroup": "chest",
         "fromKg": 60, "toKg": 62.5, "reasoning": "Clean overload signal."}
        """)

        XCTAssertEqual(card, .progression(
            exercise: "Bench Press (Barbell)",
            muscleGroup: .chest,
            fromKg: 60,
            toKg: 62.5,
            reasoning: "Clean overload signal."
        ))
    }

    func testDecodesAStoredRecoveryCard() throws {
        let card = try decode("""
        {"kind": "recovery", "reasoning": "Rest first.",
         "metrics": {"sessions": 6, "trainingDays": 6, "averageRPE": 8.5, "suggestedRestHours": 48}}
        """)

        XCTAssertEqual(card, .recovery(
            reasoning: "Rest first.",
            metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.5)
        ))
    }

    /// A week without a logged RPE is stored without the `averageRPE` key.
    func testDecodesAStoredRecoveryCardWithoutRPE() throws {
        let card = try decode("""
        {"kind": "recovery", "reasoning": "Rest first.",
         "metrics": {"sessions": 7, "trainingDays": 7, "suggestedRestHours": 72}}
        """)

        XCTAssertEqual(card, .recovery(
            reasoning: "Rest first.",
            metrics: RecoveryMetrics(sessions: 7, trainingDays: 7, averageRPE: nil)
        ))
    }

    func testDecodesAStoredImbalanceCard() throws {
        let card = try decode("""
        {"kind": "imbalance", "groupA": "chest", "perWeekA": 3, "groupB": "legs", "perWeekB": 0.8,
         "reasoning": "Add legs."}
        """)

        XCTAssertEqual(card, .imbalance(groupA: .chest, perWeekA: 3, groupB: .legs, perWeekB: 0.8, reasoning: "Add legs."))
    }

    func testDecodesAStoredNoteCard() throws {
        let card = try decode(#"{"kind": "note", "title": "Pull-ups", "text": "Add a rep."}"#)

        XCTAssertEqual(card, .note(title: "Pull-ups", text: "Add a rep."))
    }

    /// Stored muscle groups are the enum's raw values; the model's display
    /// spelling is mapped by the validator and never reaches the store.
    func testRejectsAStoredCardWithAnUnknownMuscleGroup() {
        XCTAssertThrowsError(try decode("""
        {"kind": "progression", "exercise": "Bench Press", "muscleGroup": "Pecs",
         "fromKg": 60, "toKg": 62.5, "reasoning": "Clean."}
        """))
    }

    /// A missing mean RPE stays missing: no `null` placeholder that could
    /// decode as a figure.
    func testRecoveryWithoutRPEOmitsIt() throws {
        let card = AnalysisReportCard.recovery(
            reasoning: "Rest.",
            metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil)
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any]
        )
        let metrics = try XCTUnwrap(object["metrics"] as? [String: Any])

        XCTAssertNil(metrics["averageRPE"])
        XCTAssertEqual(metrics["suggestedRestHours"] as? Int, 48)
    }

    // MARK: - Helpers

    private func decode(_ json: String) throws -> AnalysisReportCard {
        try JSONDecoder().decode(AnalysisReportCard.self, from: Data(json.utf8))
    }
}
