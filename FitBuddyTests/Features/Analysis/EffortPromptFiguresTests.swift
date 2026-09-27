import XCTest
@testable import FitBuddy

/// Unit tests for `EffortPromptFigures` (#245, US-18 AC1/AC2, ADR-015 §2):
/// every value under its source label, missing values left out, no scale
/// combined with another.
final class EffortPromptFiguresTests: XCTestCase {
    // MARK: - Labels (AC1)

    func testHevyRPEIsLabelledAsTheSessionMean() {
        XCTAssertEqual(EffortPromptFigures.labelledValues(of: summary(rpe: 7.5)), ["mean RPE 7.5"])
    }

    func testStravaRelativeEffortCarriesItsSourceLabel() {
        let values = EffortPromptFigures.labelledValues(of: summary(cardio: CardioMetrics(relativeEffort: 82)))

        XCTAssertEqual(values, ["Strava Relative Effort 82"])
    }

    /// Each Polar value under its own label, and Polar's RPE as a level name —
    /// never a number (ADR-015 §5).
    func testEveryPolarValueCarriesItsOwnLabel() {
        let values = EffortPromptFigures.labelledValues(of: summary(cardio: CardioMetrics(
            cardioLoad: 64.34,
            muscleLoad: 12,
            perceivedLoad: 70.5,
            userRPE: .hard
        )))

        XCTAssertEqual(values, [
            "Polar Cardio Load 64.3",
            "Polar Muscle Load 12",
            "Polar Perceived Load 70.5",
            "Polar RPE \"hard\"",
        ])
    }

    /// The six labels of ADR-015 §2, as exact strings in one place: renaming
    /// one in code must fail here rather than drift silently from the ADR.
    /// Five are `EffortScale` labels; "Polar RPE" is the level label that has
    /// no scale (ADR-015 §5).
    func testTheLabelsAreExactlyThoseOfADR015() {
        XCTAssertEqual(EffortScale.allCases.map(\.label), [
            "RPE",
            "Strava Relative Effort",
            "Polar Cardio Load",
            "Polar Perceived Load",
            "Polar Muscle Load",
        ])

        let labels = EffortPromptFigures.values(of: summary(rpe: 8, cardio: CardioMetrics(
            relativeEffort: 45,
            cardioLoad: 30,
            muscleLoad: 12,
            perceivedLoad: 70,
            userRPE: .hard
        ))).map(\.label)

        XCTAssertEqual(labels, [
            "mean RPE",
            "Strava Relative Effort",
            "Polar Cardio Load",
            "Polar Muscle Load",
            "Polar Perceived Load",
            "Polar RPE",
        ])
    }

    /// AC2: two scales on one session are listed side by side — two labelled
    /// values, never one combined figure.
    func testTwoScalesOnOneSessionStayTwoSeparateValues() {
        let values = EffortPromptFigures.labelledValues(of: summary(
            rpe: 8,
            cardio: CardioMetrics(relativeEffort: 45, cardioLoad: 30)
        ))

        XCTAssertEqual(values, ["mean RPE 8", "Strava Relative Effort 45", "Polar Cardio Load 30"])
    }

    // MARK: - Missing values

    func testASessionWithoutEffortHasNoValues() {
        XCTAssertEqual(EffortPromptFigures.labelledValues(of: summary(cardio: CardioMetrics(averageHeartRate: 140))), [])
        XCTAssertEqual(EffortPromptFigures.labelledValues(of: summary()), [])
        XCTAssertFalse(EffortPromptFigures.hasEffort(summary()))
    }

    /// Polar's legacy `training_load` has no label and never reaches the
    /// prompt (ADR-015 §2) — nor does it count as effort.
    func testTheLegacyPolarTrainingLoadIsNeverAnEffortValue() {
        let legacy = summary(cardio: CardioMetrics(trainingLoad: 120))

        XCTAssertEqual(EffortPromptFigures.labelledValues(of: legacy), [])
        XCTAssertFalse(EffortPromptFigures.hasEffort(legacy))
    }

    /// A zero is "not measured", not the easiest session on record.
    func testAZeroScoreIsLeftOut() {
        let values = EffortPromptFigures.labelledValues(of: summary(cardio: CardioMetrics(
            relativeEffort: 0,
            cardioLoad: 0,
            muscleLoad: 0,
            perceivedLoad: 0
        )))

        XCTAssertEqual(values, [])
    }

    /// A zero mean RPE is "not measured" too, as in `EffortScale.value`: no
    /// "mean RPE" in the prompt, and no effort for the AC6 hint.
    func testAZeroMeanRPEIsLeftOutAndCountsAsNoEffort() {
        let zero = summary(rpe: 0)

        XCTAssertEqual(EffortPromptFigures.labelledValues(of: zero), [])
        XCTAssertFalse(EffortPromptFigures.hasEffort(zero))
        XCTAssertFalse(EffortPromptFigures.containsEffort([zero]))
    }

    /// Product-owner decision on #245: "none" and a label this build could not
    /// read count as missing.
    func testPolarRPENoneAndUnknownCountAsMissing() {
        XCTAssertNil(EffortPromptFigures.polarRPELevel(.none))
        XCTAssertNil(EffortPromptFigures.polarRPELevel(.unknown))
        XCTAssertEqual(EffortPromptFigures.labelledValues(of: summary(cardio: CardioMetrics(userRPE: PolarUserRPE.none))), [])
        XCTAssertEqual(EffortPromptFigures.labelledValues(of: summary(cardio: CardioMetrics(userRPE: .unknown))), [])
    }

    /// Every other level has a name, and no name is a number.
    func testEveryRatedPolarLevelHasANameThatIsNoNumber() {
        for level in PolarUserRPE.allCases where level != .none && level != .unknown {
            let name = EffortPromptFigures.polarRPELevel(level)
            XCTAssertNotNil(name, level.rawValue)
            XCTAssertNil(name.flatMap(Double.init), level.rawValue)
        }
    }

    /// Grouping by scale keeps each scale apart and in session order — it
    /// never merges two scales, and never aggregates within one.
    func testGroupingByScaleKeepsEveryScaleApart() {
        let first = summary(cardio: CardioMetrics(relativeEffort: 82, cardioLoad: 40))
        let second = summary(rpe: 7, cardio: CardioMetrics(relativeEffort: 61))

        let groups = EffortPromptFigures.byScale([first, second])

        XCTAssertEqual(groups.map(\.label), ["mean RPE", "Strava Relative Effort", "Polar Cardio Load"])
        XCTAssertEqual(groups.map { $0.entries.map(\.text) }, [["7"], ["82", "61"], ["40"]])
    }

    // MARK: - Any effort in a window (AC6)

    func testAWindowContainsEffortWhenAnySessionCarriesAValue() {
        XCTAssertTrue(EffortPromptFigures.containsEffort([summary(), summary(cardio: CardioMetrics(userRPE: .easy))]))
        XCTAssertFalse(EffortPromptFigures.containsEffort([summary(), summary(cardio: CardioMetrics(trainingLoad: 80))]))
        XCTAssertFalse(EffortPromptFigures.containsEffort([]))
    }

    // MARK: - Helpers

    private func summary(rpe: Double? = nil, cardio: CardioMetrics? = nil) -> WorkoutSummary {
        WorkoutSummary(
            id: "s-1",
            title: "Session",
            startTime: Date(timeIntervalSince1970: 1_750_000_000),
            volumeKg: 0,
            exerciseCount: 0,
            countedSetCount: 0,
            cardio: cardio,
            averageRPE: rpe
        )
    }
}
