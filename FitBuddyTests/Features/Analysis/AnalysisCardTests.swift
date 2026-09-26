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

    func testDecodesARepProgressionCard() throws {
        let card = try decode("""
        {"kind": "repProgression", "exercise": "Lateral Raise (Dumbbell)", "muscleGroup": "Shoulders",
         "weightKg": 10, "fromReps": 12, "toReps": 14, "reasoning": "Earn the next dumbbell with reps."}
        """)

        XCTAssertEqual(card, .repProgression(
            exercise: "Lateral Raise (Dumbbell)",
            muscleGroup: "Shoulders",
            weightKg: 10,
            fromReps: 12,
            toReps: 14,
            reasoning: "Earn the next dumbbell with reps."
        ))
        XCTAssertEqual(card.kind, .repProgression)
        XCTAssertEqual(card.prose, "Earn the next dumbbell with reps.")
    }

    /// Reps are whole numbers: a rep count sent as a fraction is not the
    /// schema.
    func testRejectsRepsSentAsAFraction() {
        XCTAssertThrowsError(try decode("""
        {"kind": "repProgression", "exercise": "Row", "muscleGroup": "Back",
         "weightKg": 50, "fromReps": 8.5, "toReps": 10, "reasoning": "More."}
        """))
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

    func testDecodesAMetricCard() throws {
        let card = try decode("""
        {"kind": "metric", "label": "Weekly distance", "from": 32, "to": 35,
         "unit": "kilometers", "reasoning": "Held for three weeks.", "source": "Run"}
        """)

        XCTAssertEqual(card, .metric(
            label: "Weekly distance",
            from: 32,
            to: 35,
            unit: .kilometers,
            reasoning: "Held for three weeks.",
            source: "Run"
        ))
        XCTAssertEqual(card.kind, .metric)
    }

    /// Every unit the schema offers decodes to its case; an invented one does
    /// not, so a card in a unit the app cannot format never reaches a view.
    func testDecodesEveryMetricUnitAndRejectsAnUnknownOne() throws {
        for unit in MetricUnit.allCases {
            let card = try decode("""
            {"kind": "metric", "label": "Figure", "from": 5, "to": 6,
             "unit": "\(unit.rawValue)", "reasoning": "Because.", "source": ""}
            """)
            guard case let .metric(_, _, _, decoded, _, _) = card else {
                return XCTFail("expected a metric card")
            }
            XCTAssertEqual(decoded, unit)
        }

        XCTAssertThrowsError(try decode("""
        {"kind": "metric", "label": "Figure", "from": 5, "to": 6,
         "unit": "furlongs", "reasoning": "Because.", "source": ""}
        """))
    }

    /// The one optional key across every card: a model that leaves the header
    /// label out sends a card without a source, not a broken one.
    func testAMetricCardWithoutASourceDecodesWithAnEmptyOne() throws {
        let card = try decode("""
        {"kind": "metric", "label": "Weekly distance", "from": 32, "to": 35,
         "unit": "kilometers", "reasoning": "Held for three weeks."}
        """)

        guard case let .metric(_, _, _, _, _, source) = card else {
            return XCTFail("expected a metric card")
        }
        XCTAssertEqual(source, "")
    }

    func testDecodesAnInterferenceCard() throws {
        let card = try decode("""
        {"kind": "interference", "strengthDays": 4, "cardioDays": 4, "overlapDays": 3,
         "reasoning": "Move one run."}
        """)

        XCTAssertEqual(card, .interference(
            strengthDays: 4,
            cardioDays: 4,
            overlapDays: 3,
            reasoning: "Move one run."
        ))
    }

    func testDecodesANoteCard() throws {
        let card = try decode("""
        {"kind": "note", "title": "Pull-ups", "text": "Add one rep per set first."}
        """)

        XCTAssertEqual(card, .note(title: "Pull-ups", text: "Add one rep per set first."))
    }

    func testEveryCardSurvivesAnEncodeDecodeRoundTrip() throws {
        for card in AnalysisReportFactory.progress.cards {
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
            from: Data(AnalysisReportFactory.progressJSON.utf8)
        )

        XCTAssertEqual(report, AnalysisReportFactory.progress)
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
