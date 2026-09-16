import XCTest
@testable import FitBuddy

/// Unit tests for `WorkingSet` and `ExerciseHistoryEntry.heaviestWorkingSet`
/// (#173): which set a load recommendation starts from. The validation of
/// #175 relies on exactly this rule.
final class WorkingSetTests: XCTestCase {
    func testACountedSetWithWeightAndRepsIsAWorkingSet() {
        XCTAssertEqual(WorkingSet(set: set(.normal, 60, 5)), WorkingSet(weightKg: 60, reps: 5))
        XCTAssertNotNil(WorkingSet(set: set(.dropset, 50, 8)))
        XCTAssertNotNil(WorkingSet(set: set(.failure, 55, 6)))
    }

    func testWarmUpsAndUnknownSetsAreNoWorkingSets() {
        XCTAssertNil(WorkingSet(set: set(.warmup, 60, 5)))
        XCTAssertNil(WorkingSet(set: set(.unknown, 60, 5)))
    }

    /// Bodyweight, a loaded carry, and a set started but not completed.
    func testSetsMissingWeightOrRepsAreNoWorkingSets() {
        XCTAssertNil(WorkingSet(set: set(.normal, nil, 12)))
        XCTAssertNil(WorkingSet(set: set(.normal, 0, 12)))
        XCTAssertNil(WorkingSet(set: set(.normal, 32, nil)))
        XCTAssertNil(WorkingSet(set: set(.normal, 60, 0)))
    }

    /// By weight, not by Epley: 60 × 8 projects higher, 65 kg is on the bar.
    func testTheHeaviestWorkingSetIsChosenByWeight() {
        let entry = entry([set(.warmup, 70, 3), set(.normal, 60, 8), set(.normal, 65, 3)])

        XCTAssertEqual(entry.heaviestWorkingSet, WorkingSet(weightKg: 65, reps: 3))
    }

    func testTiesAtTheSameWeightAreBrokenByReps() {
        let entry = entry([set(.normal, 65, 3), set(.normal, 65, 5), set(.normal, 65, 4)])

        XCTAssertEqual(entry.heaviestWorkingSet, WorkingSet(weightKg: 65, reps: 5))
    }

    func testASessionWithoutWorkingSetsHasNoWorkingWeight() {
        XCTAssertNil(entry([set(.warmup, 40, 10), set(.normal, nil, 12)]).heaviestWorkingSet)
    }

    /// The text and the rounded value are the ones the prompt states.
    func testWeightIsStatedAtThePromptsPrecision() {
        let working = WorkingSet(weightKg: 61.254, reps: 5)

        XCTAssertEqual(working.weightText, "61.25")
        XCTAssertEqual(working.roundedWeightKg, 61.25)
    }

    // MARK: - Helpers

    private func entry(_ sets: [SetDetail]) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(workoutID: "w", sessionStart: Date(timeIntervalSince1970: 0), sets: sets)
    }

    private func set(_ type: SetType, _ weightKg: Double?, _ reps: Int?) -> SetDetail {
        SetDetail(index: 0, type: type, weightKg: weightKg, reps: reps,
                  distanceMeters: nil, durationSeconds: nil, rpe: nil)
    }
}
