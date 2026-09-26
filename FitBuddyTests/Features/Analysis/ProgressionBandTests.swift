import XCTest
@testable import FitBuddy

/// The load range of ADR-013 (#232): a ceiling by muscle group, a floor of
/// one step, rounded to the exercise's granularity.
final class ProgressionBandTests: XCTestCase {
    // MARK: - Ceiling by group

    func testLargeGroupsGetTenPercentAndSmallOnesFive() {
        XCTAssertEqual(ProgressionBand.share(for: .legs), 0.10)
        XCTAssertEqual(ProgressionBand.share(for: .back), 0.10)
        XCTAssertEqual(ProgressionBand.share(for: .chest), 0.10)
        XCTAssertEqual(ProgressionBand.share(for: .shoulders), 0.05)
        XCTAssertEqual(ProgressionBand.share(for: .arms), 0.05)
        XCTAssertEqual(ProgressionBand.share(for: .core), 0.05)
    }

    /// What the title heuristic could not classify gets the cautious limit.
    func testUnclassifiedMovementsGetTheSmallGroupCeiling() {
        XCTAssertEqual(ProgressionBand.share(for: .other), 0.05)
    }

    // MARK: - The ADR's example table

    func testBenchAtSixtyRunsToSixtyFive() {
        XCTAssertEqual(ProgressionBand.range(workingKg: 60, stepKg: 2.5, group: .chest), 62.5...65)
    }

    func testSquatAtAHundredRunsToOneHundredTen() {
        XCTAssertEqual(ProgressionBand.range(workingKg: 100, stepKg: 2.5, group: .legs), 102.5...110)
    }

    /// The ceiling (10.5 kg) sits under one 2 kg step: one step is always
    /// allowed, so the range is that step and nothing more.
    func testALightExerciseKeepsExactlyOneStep() {
        XCTAssertEqual(ProgressionBand.range(workingKg: 10, stepKg: 2, group: .shoulders), 12...12)
    }

    /// A ceiling exactly on a step includes it: 25 kg + 5 % = 26.25, one 2.5
    /// kg step is 27.5 — over the ceiling, so the floor carries it.
    func testTheFloorCarriesAStepOverTheCeiling() {
        XCTAssertEqual(ProgressionBand.range(workingKg: 25, stepKg: 2.5, group: .arms), 27.5...27.5)
    }

    /// 66 / 2.5 is 2.4 in exact arithmetic and 2.3999… in floating point; the
    /// tolerance keeps it from flooring to one step short.
    func testAMultipleOnTheCeilingIsNotLostToFloatingPoint() {
        XCTAssertEqual(ProgressionBand.range(workingKg: 50, stepKg: 2.5, group: .back), 52.5...55)
        XCTAssertEqual(ProgressionBand.range(workingKg: 200, stepKg: 2.5, group: .legs), 202.5...220)
    }

    // MARK: - Per listed exercise

    func testABarbellExerciseStepsByTheBarbellStepWhateverIsListed() {
        let bench = ListedExercise(
            title: "Bench Press (Barbell)",
            muscleGroup: .chest,
            workingSet: WorkingSet(weightKg: 60, reps: 5),
            smallestStepKg: 5
        )
        XCTAssertEqual(ProgressionBand.stepKg(for: bench), 2.5)
        XCTAssertEqual(ProgressionBand.range(for: bench), 62.5...65)
    }

    func testAnyOtherExerciseStepsByItsListedStep() {
        let raise = ListedExercise(
            title: "Lateral Raise (Dumbbell)",
            muscleGroup: .shoulders,
            workingSet: WorkingSet(weightKg: 10, reps: 12),
            smallestStepKg: 2
        )
        XCTAssertEqual(ProgressionBand.stepKg(for: raise), 2)
        XCTAssertEqual(ProgressionBand.range(for: raise), 12...12)
    }

    /// No step logged, no range: reps are the lever there (#234).
    func testNoListedStepMeansNoRange() {
        let curl = ListedExercise(
            title: "Bicep Curl (Cable)",
            muscleGroup: .arms,
            workingSet: WorkingSet(weightKg: 25, reps: 10)
        )
        XCTAssertNil(ProgressionBand.stepKg(for: curl))
        XCTAssertNil(ProgressionBand.range(for: curl))
    }

    func testNoWorkingSetMeansNoRange() {
        let plank = ListedExercise(title: "Plank", muscleGroup: .core, workingSet: nil, smallestStepKg: 2.5)
        XCTAssertNil(ProgressionBand.range(for: plank))
    }

    // MARK: - Text

    func testARangeIsWrittenWithAnEnDashAndOneUnit() {
        XCTAssertEqual(ProgressionBand.text(62.5...65), "62.5–65 kg")
    }

    func testASingleStepIsWrittenAsOneWeight() {
        XCTAssertEqual(ProgressionBand.text(12...12), "12 kg")
    }
}
