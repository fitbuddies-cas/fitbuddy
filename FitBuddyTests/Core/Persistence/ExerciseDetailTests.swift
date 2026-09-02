import XCTest
@testable import FitBuddy

/// Unit tests for `ExerciseDetail` (#98): the totals it derives from its sets,
/// and the numbering the detail screen renders.
final class ExerciseDetailTests: XCTestCase {
    // MARK: - Derived totals

    func testDerivesVolumeAndCountFromTheSets() {
        let exercise = Self.exercise([
            Self.set(0, .warmup, weight: 60, reps: 10),
            Self.set(1, .normal, weight: 100, reps: 8),
            Self.set(2, .normal, weight: 100, reps: 6),
        ])

        XCTAssertEqual(exercise.volumeKg, 100 * 8 + 100 * 6)
        XCTAssertEqual(exercise.countedSetCount, 2)
    }

    func testDerivesTheMuscleGroupFromTheTitle() {
        XCTAssertEqual(Self.exercise([], title: "Bench Press (Barbell)").muscleGroup, .chest)
        XCTAssertEqual(Self.exercise([], title: "Back Squat").muscleGroup, .legs)
    }

    /// A set with no weight logged adds nothing to the volume but is still a
    /// set the user did.
    func testSetsWithoutAWeightAddNoVolume() {
        let exercise = Self.exercise([
            Self.set(0, .normal, weight: nil, reps: 12),
            Self.set(1, .normal, weight: nil, reps: 10),
        ])

        XCTAssertEqual(exercise.volumeKg, 0)
        XCTAssertEqual(exercise.countedSetCount, 2)
    }

    /// `SetType.countsTowardsVolume` excludes `.unknown` as well as `.warmup`,
    /// and `.unknown` is where a missing type and every future Hevy type land.
    func testUnknownSetTypesStayOutOfTheVolume() {
        let exercise = Self.exercise([
            Self.set(0, .unknown, weight: 50, reps: 10),
            Self.set(1, .normal, weight: 100, reps: 8),
        ])

        XCTAssertEqual(exercise.volumeKg, 800)
        XCTAssertEqual(exercise.countedSetCount, 1)
    }

    // MARK: - Numbering

    func testCountedSetsAreNumberedInOrder() {
        let exercise = Self.exercise([
            Self.set(0, .normal, weight: 100, reps: 8),
            Self.set(1, .normal, weight: 100, reps: 8),
            Self.set(2, .normal, weight: 100, reps: 6),
        ])

        XCTAssertEqual(exercise.numberedSets.map(\.number), [1, 2, 3])
    }

    /// A warm-up is shown but does not take a working set's number.
    func testWarmUpsAreNotNumbered() {
        let exercise = Self.exercise([
            Self.set(0, .warmup, weight: 60, reps: 10),
            Self.set(1, .normal, weight: 100, reps: 8),
            Self.set(2, .normal, weight: 100, reps: 6),
        ])

        XCTAssertEqual(exercise.numberedSets.map(\.number), [nil, 1, 2])
    }

    /// The regression behind the fix: numbering off `countsTowardsVolume` while
    /// marking off `type == .warmup` numbered `[normal, unknown, normal]` as
    /// 1, 1, 2.
    func testUnknownSetTypesAreNotNumberedEither() {
        let exercise = Self.exercise([
            Self.set(0, .normal, weight: 100, reps: 8),
            Self.set(1, .unknown, weight: 100, reps: 8),
            Self.set(2, .normal, weight: 100, reps: 6),
        ])

        XCTAssertEqual(exercise.numberedSets.map(\.number), [1, nil, 2])
    }

    /// A leading uncounted set used to be handed the number 0, which VoiceOver
    /// read out as "Set 0".
    func testALeadingUncountedSetGetsNoNumber() {
        let exercise = Self.exercise([
            Self.set(0, .unknown, weight: 100, reps: 8),
            Self.set(1, .normal, weight: 100, reps: 8),
        ])

        XCTAssertEqual(exercise.numberedSets.map(\.number), [nil, 1])
    }

    func testNumberingKeepsTheSetsInOrder() {
        let exercise = Self.exercise([
            Self.set(0, .warmup, weight: 60, reps: 10),
            Self.set(1, .normal, weight: 100, reps: 8),
        ])

        XCTAssertEqual(exercise.numberedSets.map(\.set), exercise.sets)
    }

    // MARK: - Helpers

    private static func exercise(
        _ sets: [SetDetail],
        title: String = "Bench Press (Barbell)"
    ) -> ExerciseDetail {
        ExerciseDetail(index: 0, title: title, sets: sets)
    }

    private static func set(
        _ index: Int,
        _ type: SetType,
        weight: Double?,
        reps: Int?
    ) -> SetDetail {
        SetDetail(
            index: index,
            type: type,
            weightKg: weight,
            reps: reps,
            distanceMeters: nil,
            durationSeconds: nil,
            rpe: nil
        )
    }
}
