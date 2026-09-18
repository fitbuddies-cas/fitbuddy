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
}
