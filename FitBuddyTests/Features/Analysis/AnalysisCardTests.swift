import XCTest
@testable import FitBuddy

/// Wire format of `AnalysisCard` and `AnalysisReport` (#174): one flat object
/// per card, discriminated by `kind`.
final class AnalysisCardTests: XCTestCase {
    private func decode(_ json: String) throws -> AnalysisCard {
        try JSONDecoder().decode(AnalysisCard.self, from: Data(json.utf8))
    }

    // MARK: - Card variants

    func testDecodesAProgressionCard() throws {
        let card = try decode("""
        {"kind": "progression", "exercise": "Bench Press", "muscleGroup": "Chest",
         "fromKg": 60, "toKg": 62.5, "reasoning": "Clean overload signal."}
        """)

        XCTAssertEqual(card, .progression(
            exercise: "Bench Press",
            muscleGroup: "Chest",
            fromKg: 60,
            toKg: 62.5,
            reasoning: "Clean overload signal."
        ))
        XCTAssertEqual(card.kind, .progression)
    }

    func testDecodesARecoveryCard() throws {
        let card = try decode("""
        {"kind": "recovery", "reasoning": "Six sessions in seven days.", "suggestedRestHours": 48}
        """)

        XCTAssertEqual(card, .recovery(reasoning: "Six sessions in seven days.", suggestedRestHours: 48))
    }

    func testDecodesAnImbalanceCard() throws {
        let card = try decode("""
        {"kind": "imbalance", "groupA": "Chest", "perWeekA": 3, "groupB": "Legs", "perWeekB": 1.5,
         "reasoning": "Add a leg session."}
        """)

        XCTAssertEqual(card, .imbalance(
            groupA: "Chest",
            perWeekA: 3,
            groupB: "Legs",
            perWeekB: 1.5,
            reasoning: "Add a leg session."
        ))
    }

    func testDecodesANoteCard() throws {
        let card = try decode("""
        {"kind": "note", "title": "Pull-ups", "text": "Add one rep per set first."}
        """)

        XCTAssertEqual(card, .note(title: "Pull-ups", text: "Add one rep per set first."))
    }

    func testEveryCardSurvivesAnEncodeDecodeRoundTrip() throws {
        for card in AnalysisReportFixtures.progress.cards {
            let data = try JSONEncoder().encode(card)
            XCTAssertEqual(try JSONDecoder().decode(AnalysisCard.self, from: data), card)
        }
    }

    // MARK: - Rejection

    func testRejectsAnUnknownKind() {
        XCTAssertThrowsError(try decode(#"{"kind": "cardio", "title": "Run", "text": "Go."}"#))
    }

    func testRejectsACardMissingAField() {
        XCTAssertThrowsError(try decode(#"{"kind": "recovery", "reasoning": "Rest."}"#))
    }

    /// Numbers stay numbers: a weight sent as text is not the schema.
    func testRejectsAWeightSentAsText() {
        XCTAssertThrowsError(try decode("""
        {"kind": "progression", "exercise": "Squat", "muscleGroup": "Legs",
         "fromKg": "80 kg", "toKg": 82.5, "reasoning": "Ready."}
        """))
    }

    // MARK: - Report

    func testDecodesAReportWithEveryCardKind() throws {
        let report = try JSONDecoder().decode(
            AnalysisReport.self,
            from: Data(AnalysisReportFixtures.progressJSON.utf8)
        )

        XCTAssertEqual(report, AnalysisReportFixtures.progress)
    }

    func testDecodesTheHoldVerdict() throws {
        let report = try JSONDecoder().decode(AnalysisReport.self, from: Data("""
        {"headline": "Keep going.", "verdict": "hold", "cards": [], "summary": "Stay the course."}
        """.utf8))

        XCTAssertEqual(report.verdict, .hold)
        XCTAssertEqual(report.cards, [])
    }

    func testRejectsAnUnknownVerdict() {
        XCTAssertThrowsError(try JSONDecoder().decode(AnalysisReport.self, from: Data("""
        {"headline": "Go.", "verdict": "deload", "cards": [], "summary": "Deload."}
        """.utf8)))
    }
}
