import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisPromptBuilder` (issue #30): what the prompt carries,
/// and — just as much the point — what it must never carry.
final class AnalysisPromptBuilderTests: XCTestCase {
    private var calendar: Calendar!
    /// 2025-06-15 12:26:40 UTC.
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    }

    // MARK: - AC1: muscle group breakdown

    func testPromptContainsTheMuscleGroupBreakdown() {
        let prompt = make([
            workout(daysAgo: 2, volume: 3_000, loads: [
                MuscleLoad(group: .back, volumeKg: 2_000, setCount: 12),
                MuscleLoad(group: .arms, volumeKg: 1_000, setCount: 8),
            ]),
        ])

        XCTAssertTrue(prompt.user.contains("## Muscle groups"))
        XCTAssertTrue(prompt.user.contains("Back: 2000 kg (67% of volume), 12 working sets"))
        XCTAssertTrue(prompt.user.contains("Arms: 1000 kg (33% of volume), 8 working sets"))
    }

    /// Bodyweight and time-based work carries sets but no kilograms. A share
    /// of a zero total is a division by zero dressed as "0%" — it is omitted.
    func testGroupsWithoutVolumeKeepTheirSetsAndDropTheShare() {
        let prompt = make([
            workout(daysAgo: 1, volume: 0, loads: [
                MuscleLoad(group: .core, volumeKg: 0, setCount: 9),
            ]),
        ])

        XCTAssertTrue(prompt.user.contains("Core: 0 kg, 9 working sets"))
        XCTAssertFalse(prompt.user.contains("%"))
    }

    // MARK: - AC2: volume and frequency over the last 4 weeks

    func testPromptContainsVolumeAndFrequencyForTheWindow() {
        let prompt = make([
            workout(daysAgo: 1, volume: 4_000),
            workout(daysAgo: 3, volume: 2_000),
            workout(daysAgo: 10, volume: 1_500),
        ])

        XCTAssertTrue(prompt.user.contains("Sessions: 3"))
        XCTAssertTrue(prompt.user.contains("Training days: 3 (0.8 days per week)"))
        XCTAssertTrue(prompt.user.contains("Total volume: 7500 kg"))
    }

    /// Two sessions on one day are one training day, or the frequency figure
    /// would reward splitting a session in two.
    func testSameDaySessionsCountAsOneTrainingDay() {
        let prompt = make([
            workout(daysAgo: 1, volume: 1_000),
            workout(daysAgo: 1, volume: 1_000, id: "second"),
        ])

        XCTAssertTrue(prompt.user.contains("Sessions: 2"))
        XCTAssertTrue(prompt.user.contains("Training days: 1"))
    }

    func testPromptBreaksTheWindowIntoFourWeeks() {
        let prompt = make([
            workout(daysAgo: 1, volume: 1_000),
            workout(daysAgo: 20, volume: 500),
        ])

        XCTAssertTrue(prompt.user.contains("## Volume per week"))
        XCTAssertTrue(prompt.user.contains("(most recent): 1 sessions, 1000 kg"))
        XCTAssertTrue(prompt.user.contains("(3 weeks back): 1 sessions, 500 kg"))
        XCTAssertTrue(prompt.user.contains("(2 weeks back): 0 sessions, 0 kg"))
    }

    /// Progression needs a second window — without it the prompt can state
    /// volume but never whether it is rising or falling.
    func testPromptComparesAgainstThePrecedingFourWeeks() {
        let prompt = make([
            workout(daysAgo: 2, volume: 5_000),
            workout(daysAgo: 35, volume: 3_000),
        ])

        XCTAssertTrue(prompt.user.contains("## Previous 4 weeks"))
        XCTAssertTrue(prompt.user.contains("Total volume: 3000 kg"))
        XCTAssertTrue(prompt.user.contains("Total volume: 5000 kg"))
    }

    /// A session older than both windows is outside the analysis and must not
    /// leak into either total.
    func testWorkoutsOutsideBothWindowsAreIgnored() {
        let prompt = make([
            workout(daysAgo: 2, volume: 5_000),
            workout(daysAgo: 80, volume: 9_999),
        ])

        XCTAssertFalse(prompt.user.contains("9999"))
    }

    func testSessionsAreListedNewestFirst() {
        let prompt = make([
            workout(daysAgo: 5, volume: 1_000, id: "older", title: "Older session"),
            workout(daysAgo: 1, volume: 2_000, id: "newer", title: "Newer session"),
        ])

        let newer = try? XCTUnwrap(prompt.user.range(of: "Newer session"))
        let older = try? XCTUnwrap(prompt.user.range(of: "Older session"))
        XCTAssertNotNil(newer)
        XCTAssertNotNil(older)
        if let newer, let older {
            XCTAssertTrue(newer.lowerBound < older.lowerBound)
        }
    }

    // MARK: - AC3: no external benchmarks

    /// The AC as a property of the prompt text, not of the model's goodwill.
    func testPromptCarriesNoExternalBenchmarksOrNorms() {
        let prompt = make([
            workout(daysAgo: 2, volume: 5_000, loads: [
                MuscleLoad(group: .legs, volumeKg: 5_000, setCount: 15),
            ]),
        ])

        // Every number in the user turn has to come from this user's cache.
        let forbidden = ["average", "benchmark", "standard", "typical", "percentile", "compared to other"]
        for term in forbidden {
            XCTAssertFalse(
                prompt.user.lowercased().contains(term),
                "The user prompt must not carry the notion of \(term)"
            )
        }
    }

    func testSystemPromptForbidsInventingBenchmarks() {
        let system = AnalysisPromptBuilder.systemPrompt.lowercased()

        XCTAssertTrue(system.contains("population averages"))
        XCTAssertTrue(system.contains("strength standards"))
        XCTAssertTrue(system.contains("only reference point"))
    }

    // MARK: - Disclaimer

    func testSystemPromptCarriesTheNonMedicalDisclaimer() {
        let system = AnalysisPromptBuilder.systemPrompt.lowercased()

        XCTAssertTrue(system.contains("not a medical product"))
        XCTAssertTrue(system.contains("do not diagnose"))
        XCTAssertTrue(system.contains("qualified professional"))
    }

    /// The muscle split is a keyword heuristic and the volume figure excludes
    /// bodyweight work — unstated, both produce confident nonsense.
    func testSystemPromptDeclaresTheLimitsOfTheData() {
        let system = AnalysisPromptBuilder.systemPrompt.lowercased()

        XCTAssertTrue(system.contains("heuristically"))
        XCTAssertTrue(system.contains("warm-up sets are excluded"))
    }

    // MARK: - Empty window

    /// An empty window must read as "nothing recorded", not as "trained
    /// nothing" — the two justify very different recommendations.
    func testEmptyWindowSaysSoInsteadOfListingZeroes() {
        let prompt = make([])

        XCTAssertTrue(prompt.user.contains("No workouts are recorded in this window"))
        XCTAssertFalse(prompt.user.contains("## Volume per week"))
        XCTAssertFalse(prompt.user.contains("## Muscle groups"))
    }

    /// The window header is a section of zeroes too: "Sessions: 0" next to
    /// "no workouts are recorded" contradicts the sentence it precedes.
    func testEmptyWindowStatesNoFiguresAtAll() {
        let prompt = make([])

        XCTAssertFalse(prompt.user.contains("Sessions: 0"))
        XCTAssertFalse(prompt.user.contains("Training days: 0"))
        XCTAssertFalse(prompt.user.contains("0 kg"))
    }

    /// The range still belongs in the prompt — "nothing recorded" is only
    /// meaningful with the window it refers to.
    func testEmptyWindowStillNamesTheWindow() {
        let prompt = make([])

        XCTAssertTrue(prompt.user.contains("## Last 4 weeks ("))
    }

    func testOnlyStaleWorkoutsStillCountAsAnEmptyWindow() {
        let prompt = make([workout(daysAgo: 60, volume: 5_000)])

        XCTAssertTrue(prompt.user.contains("No workouts are recorded in this window"))
    }

    // MARK: - Widened window (#87)

    /// Every header names the window that was actually analysed. A prompt
    /// saying "last 4 weeks" over eight weeks of data would have Claude read
    /// half the sessions as missing.
    func testWidenedWindowNamesItsOwnLengthInEveryHeader() {
        let prompt = make(
            [
                workout(daysAgo: 40, volume: 5_000, loads: [
                    MuscleLoad(group: .back, volumeKg: 5_000, setCount: 12),
                ]),
                workout(daysAgo: 50, volume: 4_000, id: "b"),
            ],
            window: AnalysisWindow(weeks: 8)
        )

        XCTAssertTrue(prompt.user.contains("## Last 8 weeks ("))
        XCTAssertTrue(prompt.user.contains("## Previous 8 weeks ("))
        XCTAssertTrue(prompt.user.contains("## Muscle groups (last 8 weeks)"))
        // The only "4 weeks" left is the intro naming the break itself.
        XCTAssertFalse(prompt.user.contains("## Last 4 weeks"))
        XCTAssertFalse(prompt.user.contains("## Previous 4 weeks"))
    }

    /// The break is stated, not left to be inferred from dates: unstated, the
    /// model reads the window as a normal one and recommends progression
    /// across a pause it never noticed.
    func testWidenedWindowTellsClaudeAboutTheTrainingBreak() {
        let prompt = make([workout(daysAgo: 40, volume: 5_000)], window: AnalysisWindow(weeks: 8))

        XCTAssertTrue(prompt.user.contains("I have not trained in the last 4 weeks"))
        XCTAssertTrue(prompt.user.contains("covers the last 8 weeks instead"))
    }

    func testDefaultWindowDoesNotClaimATrainingBreak() {
        let prompt = make([workout(daysAgo: 2, volume: 5_000)])

        XCTAssertFalse(prompt.user.contains("I have not trained"))
    }

    /// The frequency average divides by the window's own weeks — with the
    /// default's 4 in the denominator, 13 weeks of training would read as more
    /// than three times the training that actually happened.
    func testFrequencyAveragesOverTheWindowsOwnWeeks() {
        let prompt = make(
            [
                workout(daysAgo: 40, volume: 1_000),
                workout(daysAgo: 50, volume: 1_000, id: "b"),
                workout(daysAgo: 60, volume: 1_000, id: "c"),
                workout(daysAgo: 70, volume: 1_000, id: "d"),
            ],
            window: AnalysisWindow(weeks: 13)
        )

        XCTAssertTrue(prompt.user.contains("Training days: 4 (0.3 days per week)"))
    }

    /// One row per week of the resolved window, so the weekly section tiles it
    /// completely rather than stopping after the default's four.
    func testWeeklySectionHasOneRowPerWeekOfTheWindow() {
        let prompt = make([workout(daysAgo: 40, volume: 5_000)], window: AnalysisWindow(weeks: 8))
        let rows = prompt.user.split(separator: "\n").filter { $0.hasPrefix("- Week starting ") }

        XCTAssertEqual(rows.count, 8)
    }

    // MARK: - Determinism

    /// The prompt is data, not display text: a Swiss device must not send
    /// `48'320` where a US one sends `48,320` for identical training.
    func testFiguresAreLocaleIndependent() {
        var swiss = Calendar(identifier: .gregorian)
        swiss.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        swiss.locale = Locale(identifier: "de_CH")

        let prompt = AnalysisPromptBuilder.make(
            summaries: [workout(daysAgo: 1, volume: 48_320)],
            now: reference,
            calendar: swiss
        )

        XCTAssertTrue(prompt.user.contains("48320 kg"))
        XCTAssertFalse(prompt.user.contains("48'320"))
        XCTAssertFalse(prompt.user.contains("48,320"))
    }

    func testTheSameDataProducesTheSamePrompt() {
        let summaries = [
            workout(daysAgo: 1, volume: 1_000),
            workout(daysAgo: 6, volume: 2_000, id: "b"),
        ]

        XCTAssertEqual(make(summaries), make(summaries))
    }

    // MARK: - Helpers

    private func make(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow = .default
    ) -> AnalysisPrompt {
        AnalysisPromptBuilder.make(
            summaries: summaries,
            window: window,
            now: reference,
            calendar: calendar
        )
    }

    private func workout(
        daysAgo: Int,
        volume: Double,
        id: String = "w-1",
        title: String = "Session",
        loads: [MuscleLoad] = []
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            title: title,
            // Midday, so a whole-day offset cannot land on a window boundary
            // and make the test depend on rounding rather than on the window.
            startTime: calendar.startOfDay(for: reference)
                .addingTimeInterval(Double(-daysAgo) * 86_400 + 43_200),
            volumeKg: volume,
            exerciseCount: 4,
            countedSetCount: 12,
            muscleLoads: loads
        )
    }
}
