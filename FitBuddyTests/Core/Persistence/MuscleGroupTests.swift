import XCTest
@testable import FitBuddy

/// The title-based classification decides what the dashboard's distribution
/// chart claims about a user's training, so the ambiguous titles — the ones
/// where two rules could match — are pinned here.
final class MuscleGroupTests: XCTestCase {
    func testClassifiesCommonBarbellMovements() {
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Bench Press (Barbell)"), .chest)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Squat (Barbell)"), .legs)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Deadlift (Barbell)"), .legs)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Overhead Press (Barbell)"), .shoulders)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Bent Over Row (Barbell)"), .back)
    }

    func testClassifiesMachineAndCableWork() {
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Lat Pulldown (Cable)"), .back)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Chest Fly (Machine)"), .chest)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Triceps Pushdown (Cable)"), .arms)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Leg Extension (Machine)"), .legs)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Standing Calf Raise (Machine)"), .legs)
    }

    /// "Seated Leg Curl" contains `curl` (arms) and "Hanging Leg Raise"
    /// contains `leg` (legs) — the rule order has to resolve both.
    func testMoreSpecificRuleWinsOverGenericKeyword() {
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Seated Leg Curl (Machine)"), .legs)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Bicep Curl (Dumbbell)"), .arms)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Hanging Leg Raise"), .core)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Lateral Raise (Dumbbell)"), .shoulders)
    }

    /// "Rowing Machine" is cardio, "Upright Row" is a shoulder movement —
    /// neither may fall into the `row` rule for back work.
    func testRowKeywordDoesNotSwallowCardioOrShoulderWork() {
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Rowing Machine"), .other)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Upright Row (Barbell)"), .shoulders)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Seated Row (Cable)"), .back)
    }

    func testClassifiesCardioAndCore() {
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Treadmill Running"), .other)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Plank"), .core)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Face Pull (Cable)"), .shoulders)
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "BENCH PRESS (BARBELL)"), .chest)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "pull up"), .back)
    }

    /// An unknown movement lands in `.other` instead of being forced into a
    /// group the chart would then over-report.
    func testUnknownTitleFallsBackToOther() {
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: "Turkish Get-Up"), .other)
        XCTAssertEqual(MuscleGroup.from(exerciseTitle: ""), .other)
    }
}
