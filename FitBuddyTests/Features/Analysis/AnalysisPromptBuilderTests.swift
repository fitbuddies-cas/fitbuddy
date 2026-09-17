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

    // MARK: - Strava sessions (US-5, #144)

    /// A run is not a strength session: passed through, it would count as a
    /// training day with 0 kg and be read under rule 5 as bodyweight work.
    /// It stays out of every figure and out of the session list.
    func testStravaSessionsAreLeftOutOfEveryFigure() {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "hevy-1", title: "Push Day"),
            workout(daysAgo: 2, volume: 0, id: "strava:1", title: "Morning Run", source: .strava),
            workout(daysAgo: 3, volume: 0, id: "strava:2", title: "Evening Run", source: .strava),
        ])

        XCTAssertTrue(prompt.user.contains("Sessions: 1"))
        XCTAssertTrue(prompt.user.contains("Training days: 1"))
        XCTAssertTrue(prompt.user.contains("Push Day"))
        XCTAssertFalse(prompt.user.contains("Run"))
    }

    func testPolarSessionsAreLeftOutOfEveryFigure() {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "hevy-1", title: "Push Day"),
            workout(daysAgo: 2, volume: 0, id: "polar:1", title: "Cycling", source: .polar),
        ])

        XCTAssertTrue(prompt.user.contains("Sessions: 1"))
        XCTAssertTrue(prompt.user.contains("Training days: 1"))
        XCTAssertFalse(prompt.user.contains("Cycling"))
    }

    func testAWindowHoldingOnlyStravaSessionsReadsAsEmpty() {
        let prompt = make([
            workout(daysAgo: 2, volume: 0, id: "strava:1", title: "Morning Run", source: .strava),
        ])

        XCTAssertTrue(prompt.user.contains("No workouts are recorded in this window"))
    }

    // MARK: - Exercises (#173)

    /// AC2 of #173: the mock profile "bench 60 kg x 5, three sessions" has
    /// to reach the model as exactly that — the value a card starts from.
    func testBenchPressProfileNamesTheWorkingWeight() {
        let bench = exercise("Bench Press", volume: 4_500, sessions: 3)
        let prompt = makeWithExercises([
            (bench, progression(bench, sessions: [
                session(daysAgo: 12, sets: working(60, 5, count: 5)),
                session(daysAgo: 8, sets: working(60, 5, count: 5)),
                session(daysAgo: 3, sets: working(60, 5, count: 5)),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("## Exercises (last 4 weeks)"))
        XCTAssertTrue(prompt.user.contains("- Bench Press: 60 kg × 5 (most recent session, 2025-06-12)"))
        XCTAssertTrue(prompt.user.contains("Chest, 3 sessions, 4500 kg"))
    }

    /// AC1 of #173: at least the eight exercises with the most volume, each
    /// with weight, reps and the 1RM trend — and the cap named, so a missing
    /// exercise reads as omitted rather than untrained.
    func testListsTheExercisesWithTheMostVolumeAndNamesTheCap() throws {
        let entries = (1...12).map { index -> (ExerciseSummary, ExerciseProgression) in
            let summary = exercise("Lift \(index)", volume: Double(index) * 1_000, sessions: 2)
            return (summary, progression(summary, sessions: [
                session(daysAgo: 10, sets: working(Double(40 + index), 8)),
                session(daysAgo: 2, sets: working(Double(42 + index), 8)),
            ]))
        }
        let prompt = makeWithExercises(entries)
        let rows = try exerciseRows(prompt)

        XCTAssertEqual(rows.count, AnalysisPromptBuilder.maxListedExercises)
        XCTAssertGreaterThanOrEqual(rows.count, 8)
        // Highest volume first.
        XCTAssertTrue(rows.first?.hasPrefix("- Lift 12: 54 kg × 8") == true)
        for row in rows {
            XCTAssertTrue(row.contains(" kg × 8"), row)
            XCTAssertTrue(row.contains("e1RM "), row)
            XCTAssertTrue(row.contains("kg at first session in window"), row)
        }
        XCTAssertFalse(prompt.user.contains("- Lift 1:"))
        XCTAssertFalse(prompt.user.contains("- Lift 2:"))
        XCTAssertTrue(prompt.user.contains("10 exercises with the most volume listed; 2 more in this window omitted"))
    }

    /// The footer counts what the cap cut, not what is missing for any other
    /// reason: a top exercise without a progression is skipped, not omitted.
    func testOmittedCountsOnlyExercisesPastTheCap() throws {
        let entries = (1...11).map { index -> (ExerciseSummary, ExerciseProgression) in
            let summary = exercise("Lift \(index)", volume: Double(index) * 1_000, sessions: 1)
            return (summary, progression(summary, sessions: [session(daysAgo: 2, sets: working(50, 8))]))
        }
        // The highest-volume lift has no progression: one row fewer, but the
        // cap still cut exactly one exercise.
        let withoutTop = entries.filter { $0.0.title != "Lift 11" }
        let prompt = AnalysisPromptBuilder.make(
            summaries: [workout(daysAgo: 2, volume: 5_000)],
            exercises: entries.map { $0.0 },
            progressions: Dictionary(uniqueKeysWithValues: withoutTop.map { ($0.0.id, $0.1) }),
            now: reference,
            calendar: calendar
        )

        XCTAssertEqual(try exerciseRows(prompt).count, AnalysisPromptBuilder.maxListedExercises - 1)
        XCTAssertTrue(prompt.user.contains("; 1 more in this window omitted)"))

        let noneCut = AnalysisPromptBuilder.make(
            summaries: [workout(daysAgo: 2, volume: 5_000)],
            exercises: Array(entries.map { $0.0 }.suffix(3)),
            progressions: [:],
            now: reference,
            calendar: calendar
        )
        XCTAssertFalse(noneCut.user.contains("omitted)"))
    }

    func testFewerExercisesThanTheCapNameNoOmission() {
        let squat = exercise("Squat (Barbell)", volume: 5_000, sessions: 1)
        let prompt = makeWithExercises([
            (squat, progression(squat, sessions: [session(daysAgo: 2, sets: working(80, 5))])),
        ])

        XCTAssertFalse(prompt.user.contains("omitted)"))
    }

    /// Names travel exactly as the cache spells them: they are the key the
    /// recommendation cards are validated against (#175).
    func testExerciseNamesArePassedExactlyAsLogged() {
        let press = exercise("Überkopfdrücken (Kurzhantel)", volume: 900, sessions: 1)
        let prompt = makeWithExercises([
            (press, progression(press, sessions: [session(daysAgo: 1, sets: working(12.5, 10))])),
        ])

        XCTAssertTrue(prompt.user.contains("- Überkopfdrücken (Kurzhantel): 12.5 kg × 10"))
    }

    /// The heaviest *working* set: a warm-up is not what the user trains at,
    /// and heaviest means weight, not the best Epley projection (60 x 8
    /// projects higher than 65 x 3, but 65 kg is what was on the bar).
    func testTheWorkingSetIsTheHeaviestNonWarmUpSet() {
        let row = exercise("Bench Press", volume: 1_000, sessions: 1)
        let prompt = makeWithExercises([
            (row, progression(row, sessions: [
                session(daysAgo: 1, sets: [
                    set(0, .warmup, 70, 3),
                    set(1, .normal, 60, 8),
                    set(2, .normal, 65, 3),
                    set(3, .normal, 65, 2),
                ]),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("- Bench Press: 65 kg × 3 "))
        XCTAssertFalse(prompt.user.contains("70 kg ×"))
    }

    func testTheWorkingSetComesFromTheMostRecentSession() {
        let row = exercise("Bench Press", volume: 1_000, sessions: 2)
        let prompt = makeWithExercises([
            (row, progression(row, sessions: [
                session(daysAgo: 9, sets: working(70, 5)),
                session(daysAgo: 2, sets: working(62.5, 5)),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("- Bench Press: 62.5 kg × 5 (most recent session, 2025-06-13)"))
    }

    func testMeanRPEIsListedOnlyWhenLogged() {
        let logged = exercise("Bench Press", volume: 2_000, sessions: 1)
        let unlogged = exercise("Row", volume: 1_000, sessions: 1)
        let prompt = makeWithExercises([
            (logged, progression(logged, sessions: [
                session(daysAgo: 1, sets: [
                    set(0, .warmup, 40, 10, rpe: 5),
                    set(1, .normal, 60, 5, rpe: 7),
                    set(2, .normal, 60, 5, rpe: 8),
                ]),
            ])),
            (unlogged, progression(unlogged, sessions: [session(daysAgo: 1, sets: working(50, 10))])),
        ])

        XCTAssertTrue(prompt.user.contains("- Bench Press: 60 kg × 5, mean RPE 7.5 "))
        XCTAssertTrue(prompt.user.contains("- Row: 50 kg × 10 (most recent session"))
    }

    /// Epley at the first and the latest session of the window: 60 x 5 is
    /// 70 kg, 62.5 x 5 is 72.9 kg.
    func testOneRepMaxTrendRunsFromWindowStartToNow() {
        let row = exercise("Bench Press", volume: 3_000, sessions: 2)
        let prompt = makeWithExercises([
            (row, progression(row, sessions: [
                session(daysAgo: 20, sets: working(60, 5)),
                session(daysAgo: 2, sets: working(62.5, 5)),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("e1RM 70 kg at first session in window, 72.9 kg now (+2.9 kg)"))
    }

    /// The progression read may reach further back than the window; the
    /// trend still has to describe the window every other figure describes.
    func testSessionsBeforeTheWindowStayOutOfTheTrend() {
        let row = exercise("Bench Press", volume: 3_000, sessions: 1)
        let prompt = makeWithExercises([
            (row, progression(row, sessions: [
                session(daysAgo: 40, sets: working(100, 5)),
                session(daysAgo: 2, sets: working(60, 5)),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("e1RM 70 kg (one session, no trend yet)"))
        XCTAssertFalse(prompt.user.contains("100 kg"))
        XCTAssertFalse(prompt.user.contains("116.7"))
    }

    func testAFallingTrendAndAnUnchangedOneAreSpelledOut() {
        let falling = exercise("Squat", volume: 3_000, sessions: 2)
        let flat = exercise("Row", volume: 2_000, sessions: 2)
        let prompt = makeWithExercises([
            (falling, progression(falling, sessions: [
                session(daysAgo: 20, sets: working(90, 5)),
                session(daysAgo: 2, sets: working(87.5, 5)),
            ])),
            (flat, progression(flat, sessions: [
                session(daysAgo: 20, sets: working(50, 10)),
                session(daysAgo: 2, sets: working(50, 10)),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("105 kg at first session in window, 102.1 kg now (-2.9 kg)"))
        XCTAssertTrue(prompt.user.contains("66.7 kg at first session in window, 66.7 kg now (no change)"))
    }

    /// The flag is `ExerciseProgression.isPlateaued`, not a second rule.
    func testPlateauFlagComesFromTheProgression() {
        let stalled = exercise("Bench Press", volume: 3_000, sessions: 4)
        let fresh = exercise("Row", volume: 2_000, sessions: 3)
        let prompt = makeWithExercises([
            (stalled, progression(stalled, sessions: [
                session(daysAgo: 21, sets: working(65, 5)),
                session(daysAgo: 14, sets: working(62.5, 5)),
                session(daysAgo: 7, sets: working(62.5, 5)),
                session(daysAgo: 2, sets: working(65, 5)),
            ])),
            (fresh, progression(fresh, sessions: [
                session(daysAgo: 14, sets: working(50, 10)),
                session(daysAgo: 7, sets: working(52.5, 10)),
                session(daysAgo: 2, sets: working(55, 10)),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("Plateau: yes, no new e1RM best in the last 3 sessions"))
        XCTAssertTrue(prompt.user.contains("Plateau: too few sessions to tell"))
    }

    func testAProgressingLiftIsNoPlateau() {
        let row = exercise("Bench Press", volume: 3_000, sessions: 4)
        let prompt = makeWithExercises([
            (row, progression(row, sessions: [
                session(daysAgo: 21, sets: working(60, 5)),
                session(daysAgo: 14, sets: working(62.5, 5)),
                session(daysAgo: 7, sets: working(65, 5)),
                session(daysAgo: 2, sets: working(67.5, 5)),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("Plateau: no."))
    }

    /// The increment the system prompt caps a load increase at, taken from
    /// the user's own log — warm-ups excluded: counting the 26 kg warm-up
    /// would make the step 1 kg.
    func testSmallestLoggedStepComesFromTheWorkingWeights() {
        let press = exercise("Shoulder Press (Machine)", volume: 3_000, sessions: 2)
        let single = exercise("Row", volume: 1_000, sessions: 1)
        let prompt = makeWithExercises([
            (press, progression(press, sessions: [
                session(daysAgo: 9, sets: [set(0, .warmup, 26, 10), set(1, .normal, 25, 8)]),
                session(daysAgo: 2, sets: [set(0, .normal, 27.5, 8), set(1, .normal, 32.5, 6)]),
            ])),
            (single, progression(single, sessions: [session(daysAgo: 1, sets: working(50, 10))])),
        ])

        XCTAssertTrue(prompt.user.contains("Smallest logged step: 2.5 kg."))
        XCTAssertEqual(prompt.user.components(separatedBy: "Smallest logged step").count, 2)
    }

    /// A gap larger than `maxStepShare` of the working weight is a change of
    /// equipment, not an increment: 8 → 12 kg would be +33 % in one session.
    /// The step is left out, and rule 6 falls back to reps.
    func testALargeGapBetweenLoggedWeightsIsNoStep() {
        let raise = exercise("Lateral Raise (Dumbbell)", volume: 1_000, sessions: 2)
        let machine = exercise("Chest Press (Machine)", volume: 3_000, sessions: 2)
        let bench = exercise("Bench Press", volume: 5_000, sessions: 2)
        let prompt = makeWithExercises([
            (raise, progression(raise, sessions: [
                session(daysAgo: 9, sets: working(8, 15)),
                session(daysAgo: 2, sets: working(12, 10)),
            ])),
            (machine, progression(machine, sessions: [
                session(daysAgo: 9, sets: working(40, 12)),
                session(daysAgo: 2, sets: working(70, 8)),
            ])),
            (bench, progression(bench, sessions: [
                session(daysAgo: 9, sets: working(60, 5)),
                session(daysAgo: 2, sets: working(62.5, 5)),
            ])),
        ])

        XCTAssertEqual(prompt.user.components(separatedBy: "Smallest logged step").count, 2)
        XCTAssertTrue(prompt.user.contains("Smallest logged step: 2.5 kg."))
        XCTAssertFalse(prompt.user.contains("Smallest logged step: 4 kg"))
        XCTAssertFalse(prompt.user.contains("Smallest logged step: 30 kg"))
    }

    /// Below the share, the floor keeps a light dumbbell's real step: 2 kg on
    /// a 10 kg lateral raise is 20 %, but no more than one plate pair.
    func testASmallStepOnALightWeightIsKeptByTheFloor() {
        let raise = exercise("Lateral Raise (Dumbbell)", volume: 1_000, sessions: 2)
        let prompt = makeWithExercises([
            (raise, progression(raise, sessions: [
                session(daysAgo: 9, sets: working(8, 15)),
                session(daysAgo: 2, sets: working(10, 12)),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("Smallest logged step: 2 kg."))
    }

    /// The floor does not turn a change of dumbbells into a step: 8 → 12 kg
    /// is 4 kg, past both the share and the floor.
    func testTheFloorStillDropsAChangeOfEquipment() {
        let raise = exercise("Lateral Raise (Dumbbell)", volume: 1_000, sessions: 2)
        let prompt = makeWithExercises([
            (raise, progression(raise, sessions: [
                session(daysAgo: 9, sets: working(8, 15)),
                session(daysAgo: 2, sets: working(12, 10)),
            ])),
        ])

        XCTAssertFalse(prompt.user.contains("Smallest logged step"))
    }

    /// A step exactly at the share still counts: 2.5 kg on 25 kg is 10 %.
    func testAStepAtTheShareIsKept() {
        let curl = exercise("Bicep Curl (Cable)", volume: 1_000, sessions: 2)
        let prompt = makeWithExercises([
            (curl, progression(curl, sessions: [
                session(daysAgo: 9, sets: working(22.5, 10)),
                session(daysAgo: 2, sets: working(25, 10)),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("Smallest logged step: 2.5 kg."))
    }

    /// A set with weight but no reps — a loaded carry — is not a working set:
    /// it neither sets the working weight nor a step. Counted, 102.5 kg would
    /// make the step 2.5 kg.
    func testASetWithWeightButNoRepsIsNoWorkingSet() {
        let deadlift = exercise("Deadlift (Barbell)", volume: 5_000, sessions: 2)
        let prompt = makeWithExercises([
            (deadlift, progression(deadlift, sessions: [
                session(daysAgo: 9, sets: working(100, 5)),
                session(daysAgo: 2, sets: [
                    set(0, .normal, 105, 5),
                    SetDetail(index: 1, type: .normal, weightKg: 120, reps: nil,
                              distanceMeters: 40, durationSeconds: nil, rpe: nil),
                    SetDetail(index: 2, type: .normal, weightKg: 102.5, reps: nil,
                              distanceMeters: 40, durationSeconds: nil, rpe: nil),
                ]),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("- Deadlift (Barbell): 105 kg × 5 "))
        XCTAssertTrue(prompt.user.contains("Smallest logged step: 5 kg."))
    }

    /// Only weighted sets without reps: the line says what is missing
    /// instead of claiming nothing was logged.
    func testASessionWithWeightsButNoRepsSaysSo() {
        let carry = exercise("Farmers Walk", volume: 0, sessions: 1)
        let prompt = makeWithExercises([
            (carry, progression(carry, sessions: [
                session(daysAgo: 2, sets: [
                    SetDetail(index: 0, type: .normal, weightKg: 32, reps: nil,
                              distanceMeters: 40, durationSeconds: nil, rpe: nil),
                ]),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("- Farmers Walk: no set with both weight and reps logged"))
    }

    /// A most recent session holding only warm-ups does not hide the working
    /// weight of the session before it.
    func testTheWorkingSetComesFromTheLatestSessionWithWorkingSets() {
        let row = exercise("Bench Press", volume: 3_000, sessions: 2)
        let prompt = makeWithExercises([
            (row, progression(row, sessions: [
                session(daysAgo: 9, sets: working(60, 5)),
                session(daysAgo: 2, sets: [set(0, .warmup, 40, 10), set(1, .warmup, 50, 5)]),
            ])),
        ])

        XCTAssertTrue(prompt.user.contains("- Bench Press: 60 kg × 5 (most recent session, 2025-06-06)"))
        XCTAssertFalse(prompt.user.contains("no working sets logged"))
    }

    /// Bodyweight work has no working weight and no Epley estimate: the line
    /// says so instead of printing a zero or a trend nobody measured.
    func testBodyweightExerciseReportsRepsWithoutWeightOrTrend() throws {
        let pullUp = exercise("Pull Up", volume: 0, sessions: 2)
        let prompt = makeWithExercises([
            (pullUp, progression(pullUp, sessions: [
                session(daysAgo: 2, sets: [set(0, .normal, nil, 8), set(1, .normal, nil, 12)]),
            ])),
        ])
        let row = try XCTUnwrap(try exerciseRows(prompt).first)

        XCTAssertTrue(row.hasPrefix("- Pull Up: no weight logged, best set 12 reps"))
        XCTAssertFalse(row.contains("e1RM"))
        XCTAssertFalse(row.contains("Plateau"))
    }

    func testWeightsAreLocaleIndependent() {
        var swiss = Calendar(identifier: .gregorian)
        swiss.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        swiss.locale = Locale(identifier: "de_CH")
        let row = exercise("Bench Press", volume: 3_000, sessions: 1)

        let prompt = AnalysisPromptBuilder.make(
            summaries: [workout(daysAgo: 1, volume: 3_000)],
            exercises: [row],
            progressions: [row.id: progression(row, sessions: [session(daysAgo: 1, sets: working(62.5, 5))])],
            now: reference,
            calendar: swiss
        )

        XCTAssertTrue(prompt.user.contains("62.5 kg × 5"))
        XCTAssertFalse(prompt.user.contains("62,5"))
    }

    /// Without exercise data the section says so, rather than disappearing
    /// and leaving rule 6 pointing at nothing.
    func testMissingExerciseDataIsStatedPlainly() {
        let prompt = make([workout(daysAgo: 2, volume: 5_000)])

        XCTAssertTrue(prompt.user.contains("## Exercises (last 4 weeks)\nNo exercise-level data is available"))
    }

    func testAnEmptyWindowHasNoExerciseSection() {
        let prompt = make([])

        XCTAssertFalse(prompt.user.contains("## Exercises"))
    }

    func testWidenedWindowNamesItsLengthInTheExerciseSection() {
        let row = exercise("Bench Press", volume: 3_000, sessions: 1)
        let prompt = AnalysisPromptBuilder.make(
            summaries: [workout(daysAgo: 40, volume: 3_000)],
            exercises: [row],
            progressions: [row.id: progression(row, sessions: [session(daysAgo: 40, sets: working(60, 5))])],
            window: AnalysisWindow(weeks: 8),
            now: reference,
            calendar: calendar
        )

        XCTAssertTrue(prompt.user.contains("## Exercises (last 8 weeks)"))
        XCTAssertTrue(prompt.user.contains("- Bench Press: 60 kg × 5"))
    }

    func testPromptedExercisesRankByVolumeThenSessionsThenTitle() {
        let ranked = AnalysisPromptBuilder.promptedExercises(from: [
            exercise("B", volume: 0, sessions: 2),
            exercise("A", volume: 0, sessions: 2),
            exercise("C", volume: 0, sessions: 5),
            exercise("D", volume: 1_000, sessions: 1),
        ])

        XCTAssertEqual(ranked.map(\.title), ["D", "C", "A", "B"])
    }

    /// US-3 AC3 with exercise data in the prompt: the new section adds the
    /// user's own figures only, never a norm to compare them against.
    func testExerciseSectionCarriesNoExternalBenchmarks() {
        let bench = exercise("Bench Press", volume: 4_500, sessions: 3)
        let prompt = makeWithExercises([
            (bench, progression(bench, sessions: [
                session(daysAgo: 12, sets: working(60, 5, rpe: 7)),
                session(daysAgo: 8, sets: working(60, 5, rpe: 7)),
                session(daysAgo: 3, sets: working(60, 5, rpe: 7)),
            ])),
        ])

        let forbidden = ["average", "benchmark", "standard", "typical", "percentile", "compared to other", "norm"]
        for term in forbidden {
            XCTAssertFalse(
                prompt.user.lowercased().contains(term),
                "The user prompt must not carry the notion of \(term)"
            )
        }
    }

    /// Rule 6: recommendations name only what the Exercises section lists,
    /// in the increments the user can actually load.
    func testSystemPromptLimitsRecommendationsToTheExerciseSection() {
        let system = AnalysisPromptBuilder.systemPrompt.lowercased()

        XCTAssertTrue(system.contains("name only exercises and weights from the exercises section"))
        XCTAssertTrue(system.contains("exactly as it is listed"))
        XCTAssertTrue(system.contains("steps of 2.5 kg"))
        XCTAssertTrue(system.contains("at most the smallest step listed"))
        // The starting weight must be listed; the target is one step above it,
        // so the rule no longer forbids the weight it asks for.
        XCTAssertTrue(system.contains("or a weight it does not list as a starting point"))
        XCTAssertTrue(system.contains("a new target weight is always the listed weight of the most recent session plus one step"))
        XCTAssertFalse(system.contains("a weight that section does not contain"))
    }

    // MARK: - Training profile (US-13 AC3, #192)

    private let fullProfile = TrainingProfile(goal: .improveEndurance, experience: .oneToThreeYears)

    func testASetProfileOpensItsOwnSectionBeforeTheData() throws {
        let user = make([workout(daysAgo: 2, volume: 5_000)], profile: fullProfile).user

        let profileAt = try XCTUnwrap(user.range(of: "## Profile")?.lowerBound)
        let windowAt = try XCTUnwrap(user.range(of: "## Last 4 weeks")?.lowerBound)
        XCTAssertTrue(user.contains("Goal: improve endurance"))
        XCTAssertTrue(user.contains("Strength training experience: 1–3 years"))
        XCTAssertLessThan(profileAt, windowAt)
    }

    /// The case of every install that never answered step 4, and of everyone
    /// who skipped it: the prompt must not change by a single character. A
    /// "Profile: —" heading would read to the model as a fact about the user.
    func testWithoutAProfileThePromptIsIdenticalToTheOneBeforeTheFeature() {
        let summaries = [workout(daysAgo: 2, volume: 5_000)]

        let before = AnalysisPromptBuilder.make(summaries: summaries, now: reference, calendar: calendar)
        let empty = make(summaries, profile: TrainingProfile())

        XCTAssertEqual(before, empty)
        XCTAssertFalse(empty.user.contains("Profile"))
        XCTAssertNil(AnalysisPromptBuilder.profileSection(TrainingProfile()))
    }

    func testAHalfProfileStatesOnlyTheHalfThatWasAnswered() {
        let goalOnly = make([workout(daysAgo: 2, volume: 5_000)], profile: TrainingProfile(goal: .loseFat)).user
        let experienceOnly = make(
            [workout(daysAgo: 2, volume: 5_000)],
            profile: TrainingProfile(experience: .overThreeYears)
        ).user

        XCTAssertTrue(goalOnly.contains("Goal: lose fat"))
        XCTAssertFalse(goalOnly.contains("experience"))
        XCTAssertTrue(experienceOnly.contains("Strength training experience: more than 3 years"))
        XCTAssertFalse(experienceOnly.contains("Goal:"))
    }

    /// The analysis reads strength sessions only. A goal like "improve
    /// endurance" invites the model to reason about training the prompt does
    /// not carry, so the section says so — every time it appears.
    func testTheProfileSectionStatesThatOnlyStrengthSessionsFollow() throws {
        let section = try XCTUnwrap(AnalysisPromptBuilder.profileSection(TrainingProfile(goal: .improveEndurance)))

        XCTAssertTrue(section.contains("strength sessions only"))
        XCTAssertTrue(section.contains("do not assume anything about other training"))
    }

    /// Context about the person is context whether or not there is data — an
    /// empty window with a profile still gets the profile.
    func testTheProfileRidesAlongWithAnEmptyWindow() {
        let user = make([], profile: fullProfile).user

        XCTAssertTrue(user.contains("## Profile"))
        XCTAssertTrue(user.contains("No workouts are recorded in this window."))
    }

    /// Decision in #189: the profile goes into the user prompt as context and
    /// leaves the rules alone. "Typical for an advanced lifter" would be the
    /// population comparison rule 3 forbids, and a system prompt that changed
    /// with the profile could soften it.
    func testTheSystemPromptDoesNotChangeWithTheProfile() {
        let without = make([workout(daysAgo: 2, volume: 5_000)]).system
        let with = make([workout(daysAgo: 2, volume: 5_000)], profile: fullProfile).system

        XCTAssertEqual(with, without)
        XCTAssertEqual(with, AnalysisPromptBuilder.systemPrompt)
    }

    /// #174: the answer is a JSON report, and its prose summary keeps the
    /// 200-word limit the plain answer had.
    func testSystemPromptAsksForTheReportAsJSON() {
        let system = AnalysisPromptBuilder.systemPrompt

        XCTAssertTrue(system.contains("one JSON object that follows the response schema"))
        for key in ["headline", "verdict", "lead", "cards", "summary", "fromKg", "toKg", "suggestedRestHours"] {
            XCTAssertTrue(system.contains(key), key)
        }
        for kind in AnalysisCard.Kind.allCases {
            XCTAssertTrue(system.contains("\"\(kind.rawValue)\""), kind.rawValue)
        }
        for verdict in AnalysisVerdict.allCases {
            XCTAssertTrue(system.contains("\"\(verdict.rawValue)\""), verdict.rawValue)
        }
        XCTAssertTrue(system.contains("under 200 words"))
    }

    /// #170: thin data gets no filler cards — zero cards is a valid answer,
    /// placeholder text never is, and the lead reads on its own.
    func testSystemPromptAllowsZeroCardsAndForbidsPlaceholders() {
        let system = AnalysisPromptBuilder.systemPrompt

        XCTAssertTrue(system.contains("zero to four cards"))
        XCTAssertFalse(system.contains("one to four cards"))
        XCTAssertTrue(system.contains("return an empty array"))
        XCTAssertTrue(system.contains("Never write placeholder or filler text in any field"))
        XCTAssertTrue(system.contains("It must stand on its own"))
        XCTAssertTrue(system.contains("one to three sentences"))
    }

    /// The fields are listed in the order the schema declares them, since the
    /// order in the prompt is what asks Claude and Mistral for it.
    func testSystemPromptListsTheFieldsInSchemaOrder() throws {
        let system = AnalysisPromptBuilder.systemPrompt
        let positions = try ["- headline:", "- verdict:", "- lead:", "- summary:", "- cards:"].map {
            try XCTUnwrap(system.range(of: $0)?.lowerBound, $0)
        }

        XCTAssertEqual(positions, positions.sorted())
        // The order sentence follows the field list directly (#170 review).
        let cards = try XCTUnwrap(system.range(of: "- cards:"))
        let order = try XCTUnwrap(system.range(of: "Write the fields in this order."))
        let placeholder = try XCTUnwrap(system.range(of: "Never write placeholder"))
        XCTAssertLessThan(cards.lowerBound, order.lowerBound)
        XCTAssertLessThan(order.lowerBound, placeholder.lowerBound)
        XCTAssertFalse(system[cards.upperBound..<order.lowerBound].contains("Never write placeholder"))
    }

    // MARK: - Helpers

    private func make(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow = .default,
        profile: TrainingProfile = TrainingProfile()
    ) -> AnalysisPrompt {
        AnalysisPromptBuilder.make(
            summaries: summaries,
            window: window,
            now: reference,
            calendar: calendar,
            profile: profile
        )
    }

    private func makeWithExercises(_ entries: [(ExerciseSummary, ExerciseProgression)]) -> AnalysisPrompt {
        AnalysisPromptBuilder.make(
            summaries: [workout(daysAgo: 2, volume: 5_000)],
            exercises: entries.map { $0.0 },
            progressions: Dictionary(uniqueKeysWithValues: entries.map { ($0.0.id, $0.1) }),
            now: reference,
            calendar: calendar
        )
    }

    /// The rows of the Exercises section, in order.
    private func exerciseRows(_ prompt: AnalysisPrompt) throws -> [String] {
        let range = try XCTUnwrap(prompt.user.range(of: "## Exercises"))
        return prompt.user[range.lowerBound...]
            .split(separator: "\n")
            .filter { $0.hasPrefix("- ") }
            .map(String.init)
    }

    private func exercise(_ title: String, volume: Double, sessions: Int) -> ExerciseSummary {
        ExerciseSummary(
            id: ExerciseSummary.key(templateID: nil, title: title),
            title: title,
            muscleGroup: MuscleGroup.from(exerciseTitle: title),
            sessionCount: sessions,
            countedSetCount: sessions * 3,
            volumeKg: volume,
            lastPerformed: reference
        )
    }

    private func progression(_ summary: ExerciseSummary, sessions: [ExerciseHistoryEntry]) -> ExerciseProgression {
        ExerciseProgression(id: summary.id, title: summary.title, sessions: sessions)
    }

    private func session(daysAgo: Int, sets: [SetDetail]) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            workoutID: "w-\(daysAgo)",
            sessionStart: calendar.startOfDay(for: reference)
                .addingTimeInterval(Double(-daysAgo) * 86_400 + 43_200),
            sets: sets
        )
    }

    private func working(_ weightKg: Double, _ reps: Int, count: Int = 3, rpe: Double? = nil) -> [SetDetail] {
        (0..<count).map { set($0, .normal, weightKg, reps, rpe: rpe) }
    }

    private func set(_ index: Int, _ type: SetType, _ weightKg: Double?, _ reps: Int?, rpe: Double? = nil) -> SetDetail {
        SetDetail(
            index: index,
            type: type,
            weightKg: weightKg,
            reps: reps,
            distanceMeters: nil,
            durationSeconds: nil,
            rpe: rpe
        )
    }

    private func workout(
        daysAgo: Int,
        volume: Double,
        id: String = "w-1",
        title: String = "Session",
        source: ConnectorSource = .hevy,
        loads: [MuscleLoad] = []
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            title: title,
            // Midday, so a whole-day offset cannot land on a window boundary
            // and make the test depend on rounding rather than on the window.
            startTime: calendar.startOfDay(for: reference)
                .addingTimeInterval(Double(-daysAgo) * 86_400 + 43_200),
            source: source,
            volumeKg: volume,
            exerciseCount: 4,
            countedSetCount: 12,
            muscleLoads: loads
        )
    }
}
