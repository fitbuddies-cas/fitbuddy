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

    /// US-15 AC6: the sharpened rule 2. General training principles are
    /// established practice and the prompt says so by name, which is what
    /// keeps the model from treating "progressive overload" as the kind of
    /// outside knowledge US-3 AC3 forbids — while the ban on population
    /// comparisons and norm values stands unchanged.
    func testSystemPromptAllowsGeneralTrainingPrinciplesByName() {
        let system = AnalysisPromptBuilder.systemPrompt.lowercased()

        XCTAssertTrue(system.contains("general training principles"))
        XCTAssertTrue(system.contains("progressive overload"))
        XCTAssertTrue(system.contains("you may name them as principles"))
        XCTAssertTrue(system.contains("never invoke population averages"))
    }

    /// The whole reason endurance sessions were dropped before #183: rule 5
    /// reads a 0 kg line as bodyweight work. It is scoped to the strength
    /// sections now, and the endurance rule says the opposite for its own.
    func testSystemPromptScopesTheVolumeRuleAndStatesTheEnduranceOne() {
        let system = AnalysisPromptBuilder.systemPrompt.lowercased()

        XCTAssertTrue(system.contains("in the strength sections, volume is the sum of weight x reps"))
        XCTAssertTrue(system.contains("in the endurance sections, load is distance, time, pace and heart rate"))
        XCTAssertTrue(system.contains("rule 5 does not apply there"))
        XCTAssertTrue(system.contains("no volume in kilograms is not an absence of training load"))
        XCTAssertTrue(system.contains("week structure section is about both domains"))
    }

    /// A section that is not in the prompt describes training that was not
    /// recorded — unstated, an absent endurance section reads as "no
    /// endurance training", which is a different claim.
    func testSystemPromptSaysWhatAnAbsentSectionMeans() {
        let system = AnalysisPromptBuilder.systemPrompt.lowercased()

        XCTAssertTrue(system.contains("a section you were not given"))
        XCTAssertTrue(system.contains("did not record in this window"))
    }

    /// AC3 over a mixed window: the endurance and week-structure sections must
    /// not smuggle in a comparison the strength sections were kept free of.
    func testAMixedPromptCarriesNoExternalBenchmarksEither() {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, loads: [MuscleLoad(group: .chest, volumeKg: 3_000, setCount: 9)]),
            run(daysAgo: 2, id: "strava:1", heartRate: 150),
            run(daysAgo: 3, id: "strava:2", title: "Commute", kind: .ride, meters: 20_000, seconds: 3_000),
        ])

        let forbidden = ["average", "benchmark", "standard", "typical", "percentile", "compared to other"]
        for term in forbidden {
            XCTAssertFalse(
                prompt.user.lowercased().contains(term),
                "The user prompt must not carry the notion of \(term)"
            )
        }
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
    ///
    /// Asserted as the property of the output, not by injecting a locale.
    /// Nothing in the figure path reads one — `PromptFigures` writes integers
    /// by interpolation and decimals through `String(format:)` without a
    /// locale argument, which is POSIX by construction, and a `Calendar`'s
    /// locale never reaches a number. A test that passed `de_CH` therefore
    /// could not fail, which made it read as a guarantee it was not giving.
    /// What it does catch is the regression that matters: a `NumberFormatter`
    /// or a `display(_:locale:)` formatter introduced into the prompt, which
    /// groups thousands and moves the decimal mark on the device it runs on.
    func testFiguresCarryNoGroupingSeparatorAndAPeriodDecimalMark() {
        let prompt = make([
            workout(daysAgo: 1, volume: 48_320),
            run(daysAgo: 2, id: "strava:1", meters: 123_456, seconds: 30_600, heartRate: 148),
        ])

        XCTAssertTrue(prompt.user.contains("48320 kg"))
        XCTAssertTrue(prompt.user.contains("123 km"))
        XCTAssertTrue(prompt.user.contains("8 h 30 min"))
        XCTAssertTrue(prompt.user.contains("148 bpm"))
        for separator in ["48'320", "48,320", "48 320", "123'456", "4,03", "4 03"] {
            XCTAssertFalse(prompt.user.contains(separator), "must not group or re-punctuate \(separator)")
        }
    }

    /// The decimal mark itself, on the one figure that has one: a comma here
    /// would be a locale-aware formatter having reached the prompt.
    func testADecimalFigureUsesAPeriod() throws {
        let prompt = make([run(daysAgo: 1, id: "strava:1", meters: 5_500, seconds: 1_800)])
        let endurance = try section(prompt, "## Endurance, last 4 weeks")

        XCTAssertTrue(endurance.contains("Total distance: 5.5 km"))
        XCTAssertFalse(endurance.contains("5,5"))
    }

    func testTheSameDataProducesTheSamePrompt() {
        let summaries = [
            workout(daysAgo: 1, volume: 1_000),
            workout(daysAgo: 6, volume: 2_000, id: "b"),
        ]

        XCTAssertEqual(make(summaries), make(summaries))
    }

    // MARK: - Domain sections (US-15 AC2, #183)

    /// The filter that used to drop them was about rule 5, not about Strava:
    /// a run counted as a strength session would read as "0 kg" and produce a
    /// volume collapse that never happened. It stays out of the strength
    /// figures — and now lands in a section of its own.
    func testEnduranceSessionsStayOutOfTheStrengthFigures() throws {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "hevy-1", title: "Push Day"),
            run(daysAgo: 2, id: "strava:1"),
            run(daysAgo: 3, id: "strava:2", title: "Evening Run"),
        ])
        let strength = try section(prompt, "## Last 4 weeks")

        XCTAssertTrue(strength.contains("Sessions: 1"))
        XCTAssertTrue(strength.contains("Training days: 1"))
        XCTAssertFalse(strength.contains("Run"))
        XCTAssertTrue(try section(prompt, "## Sessions (newest first)").contains("Push Day"))
        XCTAssertTrue(try section(prompt, "## Endurance, last 4 weeks").contains("Sessions: 2"))
    }

    /// The flip of #183 in one case: the sport decides, not the source. A
    /// Strava strength session is strength work however it reached the cache.
    func testAStravaStrengthSessionLandsInTheStrengthSection() throws {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "hevy-1", title: "Push Day"),
            workout(daysAgo: 2, volume: 2_000, id: "strava:1", title: "Gym", source: .strava, kind: .strength),
        ])
        let strength = try section(prompt, "## Last 4 weeks")

        XCTAssertTrue(strength.contains("Sessions: 2"))
        XCTAssertTrue(strength.contains("Total volume: 5000 kg"))
        XCTAssertTrue(try section(prompt, "## Sessions (newest first)").contains("Gym"))
        XCTAssertFalse(prompt.user.contains("## Endurance"))
    }

    /// And the other direction: a Hevy session of treadmill sets carries the
    /// model's default `.strength`, moves no load and logged distance and
    /// time — `WorkoutSummary.isCardio` calls that endurance, so the prompt
    /// does too.
    func testAHevyCardioSessionLandsInTheEnduranceSection() throws {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "hevy-1", title: "Push Day"),
            workout(
                daysAgo: 2,
                volume: 0,
                id: "hevy-2",
                title: "Treadmill",
                distanceMeters: 5_000,
                durationSeconds: 1_800
            ),
        ])

        XCTAssertTrue(try section(prompt, "## Last 4 weeks").contains("Sessions: 1"))
        let endurance = try section(prompt, "## Endurance, last 4 weeks")
        XCTAssertTrue(endurance.contains("Sessions: 1"))
        XCTAssertTrue(endurance.contains("Total distance: 5 km"))
        // No sport was mapped, so the row says what is known and no more.
        XCTAssertTrue(endurance.contains("- Other: 1 session, 5 km, 30 min"))
    }

    /// AC3 of the issue: only endurance data, so no strength section and not
    /// one kilogram anywhere.
    func testAWindowWithoutStrengthHasNoStrengthSectionAndNoKilograms() {
        let prompt = make([run(daysAgo: 2), run(daysAgo: 4, id: "strava:2", title: "Evening Run")])

        XCTAssertFalse(prompt.user.contains("## Last 4 weeks"))
        XCTAssertFalse(prompt.user.contains("## Volume per week"))
        XCTAssertFalse(prompt.user.contains("## Muscle groups"))
        XCTAssertFalse(prompt.user.contains("## Sessions (newest first)"))
        XCTAssertFalse(prompt.user.contains("kg"))
        XCTAssertFalse(prompt.user.contains("No workouts are recorded in this window"))
        XCTAssertTrue(prompt.user.contains("## Endurance, last 4 weeks"))
    }

    /// AC1: a Hevy-only cache produces exactly the prompt it produced before
    /// the split — no empty endurance section, no week structure, and the same
    /// text as the builder that never knew about domains.
    func testAHevyOnlyWindowProducesNeitherAnEnduranceNorAWeekStructureSection() {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "hevy-1", title: "Push Day", loads: [
                MuscleLoad(group: .chest, volumeKg: 3_000, setCount: 9),
            ]),
            workout(daysAgo: 4, volume: 4_000, id: "hevy-2", title: "Pull Day"),
        ])

        XCTAssertFalse(prompt.user.contains("## Endurance"))
        XCTAssertFalse(prompt.user.contains("## Week structure"))
        XCTAssertFalse(prompt.user.contains("km"))
        XCTAssertTrue(prompt.user.contains("## Last 4 weeks"))
    }

    /// The endurance figures AC2 asks for: weekly kilometres and hours, heart
    /// rate, pace, and the trend against the previous window.
    func testTheEnduranceSectionStatesDistanceTimeHeartRateAndPace() throws {
        let prompt = make([
            run(daysAgo: 1, id: "strava:1", meters: 10_000, seconds: 3_000, heartRate: 150),
            run(daysAgo: 3, id: "strava:2", title: "Evening Run", meters: 5_000, seconds: 1_500, heartRate: 144),
            run(daysAgo: 31, id: "strava:3", title: "Old Run", meters: 8_000, seconds: 2_400),
        ])
        let endurance = try section(prompt, "## Endurance, last 4 weeks")

        XCTAssertTrue(endurance.contains("Sessions: 2"))
        XCTAssertTrue(endurance.contains("Training days: 2 (0.5 days per week)"))
        XCTAssertTrue(endurance.contains("Total distance: 15 km"))
        XCTAssertTrue(endurance.contains("Total time: 1 h 15 min"))
        XCTAssertTrue(endurance.contains("Mean heart rate: 147 bpm"))
        XCTAssertTrue(endurance.contains("Longest session: 10 km, 50 min on"))
        XCTAssertTrue(endurance.contains("- Run: 2 sessions, 15 km, 1 h 15 min, mean pace 5:00 min/km"))
        XCTAssertTrue(endurance.contains("mean heart rate 147 bpm"))

        let previous = try section(prompt, "## Previous 4 weeks (")
        XCTAssertTrue(previous.contains("endurance, for comparison"))
        XCTAssertTrue(previous.contains("Total distance: 8 km"))
    }

    /// One row per sport, so "nine sessions" cannot read as nine runs. A ride
    /// is stated in km/h — a pace per kilometre is not the unit anybody reads
    /// a ride in.
    func testEachSportGetsItsOwnRowAndRidesAreStatedInSpeed() throws {
        let prompt = make([
            run(daysAgo: 1, id: "strava:1", meters: 10_000, seconds: 3_000),
            run(daysAgo: 2, id: "strava:2", title: "Commute", kind: .ride, meters: 24_000, seconds: 3_600),
            run(daysAgo: 3, id: "polar:1", title: "Pool", source: .polar, kind: .swim, meters: 1_500, seconds: 2_100),
        ])
        let endurance = try section(prompt, "## Endurance, last 4 weeks")

        XCTAssertTrue(endurance.contains("- Run: 1 session, 10 km, 50 min, mean pace 5:00 min/km"))
        XCTAssertTrue(endurance.contains("- Ride: 1 session, 24 km, 1 h, mean speed 24 km/h"))
        XCTAssertTrue(endurance.contains("- Swim: 1 session, 1.5 km, 35 min"))
        XCTAssertFalse(endurance.contains("Ride: 1 session, 24 km, 1 h, mean pace"))
    }

    /// US-15 AC7 in the prompt: a figure the source did not record is left
    /// out, never printed as a zero the model would read as a measurement.
    func testUnrecordedEnduranceFiguresAreLeftOutRatherThanZeroed() throws {
        let prompt = make([
            run(daysAgo: 1, id: "strava:1", title: "Indoor Ride", kind: .ride, meters: nil, seconds: 3_600),
        ])
        let endurance = try section(prompt, "## Endurance, last 4 weeks")

        XCTAssertFalse(endurance.contains("Total distance"))
        XCTAssertFalse(endurance.contains("0 km"))
        XCTAssertFalse(endurance.contains("Mean heart rate"))
        XCTAssertTrue(endurance.contains("Total time: 1 h"))
        XCTAssertTrue(endurance.contains("- Ride: 1 session, 1 h"))
    }

    /// An empty previous window is a break or the start of the history, and
    /// the prompt must not decide which.
    func testAnEmptyEnduranceComparisonWindowSaysWhatItDoesNotKnow() throws {
        let prompt = make([run(daysAgo: 2)])
        let previous = try section(prompt, "## Previous 4 weeks (")

        XCTAssertTrue(previous.contains("No endurance sessions recorded"))
        XCTAssertTrue(previous.contains("do not assume which"))
    }

    /// The per-week rows the strength half has, in endurance units.
    func testTheEnduranceWeeklySectionHasOneRowPerWeekOfTheWindow() throws {
        let prompt = make([run(daysAgo: 2, meters: 12_000, seconds: 3_600)])
        let weekly = try section(prompt, "## Endurance per week")
        let rows = weekly.split(separator: "\n").filter { $0.hasPrefix("- Week starting ") }

        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(weekly.contains("(most recent): 1 sessions, 12 km, 1 h"))
        XCTAssertTrue(weekly.contains("(2 weeks back): 0 sessions"))
    }

    // MARK: - Week structure (US-15 AC2, #183)

    /// The gate is endurance, not both domains (#184 review, finding 5): a
    /// Hevy-only prompt is unchanged (#183 AC1), while a Strava-only one needs
    /// the day count the app overrules it on. Replaces
    /// `testTheWeekStructureSectionAppearsOnlyWhenBothDomainsHaveSessions`.
    func testTheWeekStructureSectionAppearsWheneverThereIsEndurance() {
        let both = make([workout(daysAgo: 1, volume: 3_000), run(daysAgo: 2)])
        let strengthOnly = make([workout(daysAgo: 1, volume: 3_000)])
        let enduranceOnly = make([run(daysAgo: 2)])

        XCTAssertTrue(both.user.contains("## Week structure (last 4 weeks)"))
        XCTAssertFalse(strengthOnly.user.contains("## Week structure"))
        XCTAssertTrue(enduranceOnly.user.contains("## Week structure (last 4 weeks)"))
    }

    /// An endurance-only window gets the streak and the last seven days and
    /// nothing else: its own training days are in the endurance header, and
    /// "Days with strength only: 0" would restate the absence of a section the
    /// model was told not to reason about.
    func testAnEnduranceOnlyWeekStructureCarriesOnlyTheCrossWeekFigures() throws {
        let prompt = make([
            run(daysAgo: 1, id: "s1"),
            run(daysAgo: 2, id: "s2", title: "Evening Run"),
        ])
        let structure = try section(prompt, "## Week structure")

        XCTAssertTrue(
            structure.contains("Last 7 days: 2 training days (0 strength sessions, 2 endurance sessions)"),
            structure
        )
        XCTAssertTrue(structure.contains("Longest streak of consecutive training days: 2 days ("))
        XCTAssertFalse(structure.contains("Days with strength only"))
        XCTAssertFalse(structure.contains("Days with both"))
        XCTAssertFalse(structure.contains("Rest days"))
        XCTAssertFalse(structure.contains("Training days:"))
    }

    /// Six runs on six days: the prompt states the count US-3 AC6 turns on,
    /// where before #184 no such line existed for a cache without strength.
    func testAnEnduranceOnlyWeekReportsSixTrainingDays() throws {
        let prompt = make((0..<6).map { run(daysAgo: $0, id: "s\($0)") })
        let structure = try section(prompt, "## Week structure")

        XCTAssertTrue(
            structure.contains("Last 7 days: 6 training days (0 strength sessions, 6 endurance sessions)"),
            structure
        )
    }

    func testTheWeekStructureCountsDaysPerDomainAndTheLongestStreak() throws {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "h1"),
            workout(daysAgo: 2, volume: 3_000, id: "h2"),
            // Same day as the lift above — one training day carrying both.
            run(daysAgo: 2, id: "s1"),
            run(daysAgo: 3, id: "s2", title: "Evening Run"),
            run(daysAgo: 9, id: "s3", title: "Long Run"),
        ])
        let structure = try section(prompt, "## Week structure")

        XCTAssertTrue(structure.contains("Training days: 4 of 28 (1.0 days per week)"))
        XCTAssertTrue(structure.contains("Days with strength only: 1"))
        XCTAssertTrue(structure.contains("Days with endurance only: 2"))
        XCTAssertTrue(structure.contains("Days with both: 1"))
        XCTAssertTrue(structure.contains("Rest days: 24"))
        XCTAssertTrue(structure.contains("Longest streak of consecutive training days: 3 days ("))
    }

    /// The week structure counts days, not sessions: two sessions on one day
    /// are one training day, in both domains and in the streak.
    func testTwoSessionsOnOneDayAreOneTrainingDayInTheWeekStructure() throws {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "h1"),
            workout(daysAgo: 1, volume: 2_000, id: "h2"),
            run(daysAgo: 5, id: "s1"),
        ])
        let structure = try section(prompt, "## Week structure")

        XCTAssertTrue(structure.contains("Training days: 2 of 28"))
        XCTAssertTrue(structure.contains("Longest streak of consecutive training days: 1 day ("))
    }

    // MARK: - Last 7 days across both domains (US-15 AC3, #184)

    /// The issue's first acceptance criterion: 3 strength sessions and 4 runs
    /// on 6 different days reach the model as 6 training days, where the prompt
    /// used to report only the 3 strength days.
    func testTheWeekStructureReportsSixTrainingDaysForThreeLiftsAndFourRuns() throws {
        let prompt = make([
            workout(daysAgo: 0, volume: 3_000, id: "h1"),
            workout(daysAgo: 1, volume: 3_000, id: "h2"),
            workout(daysAgo: 2, volume: 3_000, id: "h3"),
            // Same day as the third lift: 7 sessions on 6 distinct days.
            run(daysAgo: 2, id: "s1"),
            run(daysAgo: 3, id: "s2"),
            run(daysAgo: 4, id: "s3"),
            run(daysAgo: 5, id: "s4"),
        ])
        let structure = try section(prompt, "## Week structure")

        XCTAssertTrue(
            structure.contains("Last 7 days: 6 training days (3 strength sessions, 4 endurance sessions)"),
            structure
        )
    }

    /// The line covers the last seven days, not the whole window: an older
    /// session is in the window's own counts and out of this one.
    func testTheLastSevenDaysLineIgnoresOlderSessions() throws {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "h1"),
            workout(daysAgo: 12, volume: 3_000, id: "h2"),
            run(daysAgo: 2, id: "s1"),
            run(daysAgo: 20, id: "s2"),
        ])
        let structure = try section(prompt, "## Week structure")

        XCTAssertTrue(structure.contains("Training days: 4 of 28"))
        XCTAssertTrue(
            structure.contains("Last 7 days: 2 training days (1 strength session, 1 endurance session)"),
            structure
        )
    }

    /// A day carrying both domains is one training day on this line as well.
    func testTheLastSevenDaysLineCountsADayCarryingBothOnce() throws {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "h1"),
            run(daysAgo: 1, id: "s1"),
        ])
        let structure = try section(prompt, "## Week structure")

        XCTAssertTrue(
            structure.contains("Last 7 days: 1 training day (1 strength session, 1 endurance session)"),
            structure
        )
    }

    /// The line carries the figure the recovery card prints as "Avg HR", not
    /// the endurance section's window mean — otherwise a card reason could cite
    /// one number above a label showing another (#184 review, finding 4).
    func testTheLastSevenDaysLineCarriesTheCardsHeartRate() throws {
        let summaries = [
            workout(daysAgo: 1, volume: 3_000, id: "h1"),
            run(daysAgo: 2, id: "s1", heartRate: 150),
            run(daysAgo: 3, id: "s2", heartRate: 160),
            // Older than the week, and far off the week's mean: it moves the
            // endurance section's figure and must not move this one.
            run(daysAgo: 20, id: "s3", heartRate: 100),
        ]
        let prompt = make(summaries)
        let structure = try section(prompt, "## Week structure")
        let metrics = RecoveryMetrics(summaries: summaries, details: [], now: reference, calendar: calendar)

        XCTAssertEqual(metrics.averageHeartRate, 155)
        XCTAssertTrue(structure.contains("mean heart rate 155 bpm"), structure)
    }

    /// Nothing in the week wore a strap: the figure is omitted, not zero
    /// (US-15 AC7).
    func testTheLastSevenDaysLineOmitsAHeartRateNobodyRecorded() throws {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "h1"),
            run(daysAgo: 2, id: "s1"),
        ])
        let structure = try section(prompt, "## Week structure")

        XCTAssertTrue(structure.contains("Last 7 days:"), structure)
        XCTAssertFalse(structure.contains("mean heart rate"), structure)
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

    /// With strength data alone, a goal like "improve endurance" invites the
    /// model to reason about training the prompt does not carry, so the
    /// section says what is in it — every time it appears.
    func testTheProfileSectionStatesThatOnlyStrengthSessionsFollow() throws {
        let section = try XCTUnwrap(AnalysisPromptBuilder.profileSection(TrainingProfile(goal: .improveEndurance)))

        XCTAssertTrue(section.contains("strength sessions only"))
        XCTAssertTrue(section.contains("do not assume anything about other training"))
    }

    /// And once the window carries endurance work, the same line has to say
    /// so: "strength sessions only" over an endurance section would be the
    /// prompt contradicting itself (#183).
    func testTheProfileSectionNamesBothDomainsWhenTheWindowCarriesThem() {
        let mixed = make(
            [workout(daysAgo: 1, volume: 3_000), run(daysAgo: 2)],
            profile: fullProfile
        ).user
        let strengthOnly = make([workout(daysAgo: 1, volume: 3_000)], profile: fullProfile).user

        XCTAssertTrue(mixed.contains("covers my strength and endurance sessions"))
        XCTAssertFalse(mixed.contains("strength sessions only"))
        XCTAssertTrue(strengthOnly.contains("covers my strength sessions only"))
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

    // MARK: - Analysis profile (US-15 AC1, #185)

    /// The default and the prompt of #183/#184: every section the window
    /// supports.
    func testOverallLoadBuildsBothDomainSectionsAndTheWeekStructure() {
        let prompt = make(
            [workout(daysAgo: 2, volume: 5_000), run(daysAgo: 3)],
            analysisProfile: .overallLoad
        ).user
        XCTAssertTrue(prompt.contains("## Last 4 weeks"))
        XCTAssertTrue(prompt.contains("## Endurance, last 4 weeks"))
        XCTAssertTrue(prompt.contains("## Week structure"))
        XCTAssertTrue(prompt.contains("Days with both:"))
    }

    func testTheStrengthProfileLeavesTheEnduranceSectionsOut() {
        let prompt = make(
            [workout(daysAgo: 2, volume: 5_000), run(daysAgo: 3)],
            analysisProfile: .strength
        ).user
        XCTAssertTrue(prompt.contains("## Last 4 weeks"))
        XCTAssertFalse(prompt.contains("## Endurance"))
        XCTAssertFalse(prompt.contains("Morning Run"))
    }

    /// AC5: an endurance analysis names no kilogram value, because the whole
    /// strength half — figures, session list and Exercises section — is gone.
    func testTheEnduranceProfileLeavesEveryKilogramOut() {
        let prompt = make(
            [workout(daysAgo: 2, volume: 5_000), run(daysAgo: 3)],
            analysisProfile: .endurance
        ).user
        XCTAssertTrue(prompt.contains("## Endurance, last 4 weeks"))
        XCTAssertFalse(prompt.contains("## Volume per week"))
        XCTAssertFalse(prompt.contains("## Exercises"))
        XCTAssertFalse(prompt.contains("kg"))
    }

    /// The system prompt tells the model that a missing section is training
    /// this person did not record. Under a single-domain profile that would be
    /// untrue, so the user turn says what was left out and why.
    func testASingleDomainProfileSaysWhatItLeftOut() {
        let prompt = make(
            [workout(daysAgo: 2, volume: 5_000), run(daysAgo: 3)],
            analysisProfile: .strength
        ).user
        XCTAssertTrue(prompt.contains("Analyse my strength training only"))
        XCTAssertTrue(prompt.contains("left them out of this analysis on purpose"))
    }

    func testNothingIsSaidAboutAnOmissionThatDidNotHappen() {
        let prompt = make([workout(daysAgo: 2, volume: 5_000)], analysisProfile: .strength).user
        XCTAssertFalse(prompt.contains("on purpose"))
    }

    /// The orchestrator's decision: a run costs recovery under the "Strength"
    /// profile too, so the week the app judges US-3 AC6 on is still stated.
    func testTheStrengthProfileStillStatesTheLastSevenDaysAcrossBothDomains() throws {
        let prompt = make(
            [
                workout(daysAgo: 1, volume: 5_000, id: "w-1"),
                workout(daysAgo: 2, volume: 5_000, id: "w-2"),
                run(daysAgo: 3, id: "strava:1"),
                run(daysAgo: 4, id: "strava:2"),
            ],
            analysisProfile: .strength
        )
        let structure = try section(prompt, "## Week structure")
        XCTAssertTrue(structure.contains("Last 7 days: 4 training days"))
        XCTAssertTrue(structure.contains("2 strength sessions"))
        XCTAssertTrue(structure.contains("2 endurance sessions"))
        XCTAssertTrue(structure.contains("cost the same recovery"))
        // The full structure belongs to "Overall load" — under one domain the
        // section carries the recovery week and nothing else.
        XCTAssertFalse(structure.contains("Days with both:"))
        XCTAssertFalse(structure.contains("Longest streak"))
    }

    func testTheEnduranceProfileNamesTheStrengthSessionsItLeftInTheDayCount() throws {
        let prompt = make(
            [workout(daysAgo: 1, volume: 5_000), run(daysAgo: 2)],
            analysisProfile: .endurance
        )
        let structure = try section(prompt, "## Week structure")
        XCTAssertTrue(structure.contains("I asked about my endurance training only"))
        XCTAssertTrue(structure.contains("my strength sessions are not described above"))
    }

    /// A window with one domain has nothing to leave out, so no profile adds a
    /// week-structure section to it — which is what keeps a Hevy-only prompt
    /// where #183 froze it.
    func testASingleDomainWindowHasNoWeekStructureUnderAnyProfile() {
        for profile in AnalysisProfile.allCases {
            let prompt = make([workout(daysAgo: 2, volume: 5_000)], analysisProfile: profile).user
            XCTAssertFalse(prompt.contains("## Week structure"), "\(profile)")
        }
    }

    /// US-15 AC1 over a Hevy-only cache: the profile is implicit, and the
    /// prompt is byte for byte the one every earlier build produced.
    func testAHevyOnlyUserTurnIsTheSameUnderEveryProfile() {
        let summaries = [
            workout(daysAgo: 2, volume: 5_000, id: "w-1"),
            workout(daysAgo: 9, volume: 4_000, id: "w-2"),
        ]
        let overall = make(summaries, analysisProfile: .overallLoad).user
        XCTAssertEqual(make(summaries, analysisProfile: .strength).user, overall)
        // "Endurance" cannot be chosen here — the picker does not offer it —
        // and a stale choice widens to what this window actually holds, which
        // over a cache of lifts alone is "Strength" (#185). Either way the
        // user turn is the one every build before the profile produced.
        XCTAssertEqual(make(summaries, analysisProfile: .endurance).user, overall)
    }

    func testAProfileWithoutASessionInTheWindowFallsBackToEverything() {
        let prompt = make([run(daysAgo: 2), run(daysAgo: 4, id: "strava:2")], analysisProfile: .strength).user
        XCTAssertTrue(prompt.contains("## Endurance, last 4 weeks"))
        XCTAssertFalse(prompt.contains("on purpose"))
    }

    /// US-13's profile line names what the prompt actually carries, so an
    /// endurance analysis does not claim to be about strength sessions.
    func testTheTrainingProfileLineNamesTheDomainsThePromptCarries() {
        let summaries = [workout(daysAgo: 2, volume: 5_000), run(daysAgo: 3)]
        let goal = TrainingProfile(goal: .improveEndurance)
        XCTAssertTrue(
            make(summaries, profile: goal, analysisProfile: .endurance)
                .user.contains("covers my endurance sessions only")
        )
        XCTAssertTrue(
            make(summaries, profile: goal, analysisProfile: .strength)
                .user.contains("covers my strength sessions only")
        )
        XCTAssertTrue(
            make(summaries, profile: goal, analysisProfile: .overallLoad)
                .user.contains("covers my strength and endurance sessions")
        )
    }

    /// Nothing was left out, so the section #184 built for a running week is
    /// rendered as it is — no "I asked about" sentence, and the streak and the
    /// last seven days both there.
    func testAnEnduranceOnlyWindowKeepsTheSectionItAlreadyHad() throws {
        let prompt = make(
            [run(daysAgo: 1, id: "strava:1"), run(daysAgo: 2, id: "strava:2")],
            analysisProfile: .endurance
        )
        let structure = try section(prompt, "## Week structure")
        XCTAssertFalse(structure.contains("I asked about"))
        XCTAssertTrue(structure.contains("Longest streak"))
        XCTAssertTrue(structure.contains("Last 7 days: 2 training days"))
    }

    func testTheSystemPromptExplainsADeliberatelyOmittedSection() {
        let system = AnalysisPromptBuilder.systemPrompt
        XCTAssertTrue(system.contains("chose to leave out of this analysis"))
        XCTAssertTrue(system.contains("still count towards those days and still cost recovery"))
    }

    // MARK: - Review round on #183

    /// AC1 pinned as a whole, not as a list of absences: a Hevy-only cache has
    /// to produce this exact user turn, so a reworded line inside
    /// `StrengthPromptSection` fails here rather than silently changing what
    /// every existing analysis is built from.
    ///
    /// Deliberate deviation, and the reason this is "a Hevy-only cache" and
    /// not "a Hevy-only install": a Hevy session of treadmill sets is
    /// endurance since #183 and leaves these figures. A prompt built from a
    /// cache holding one is not byte-identical to the pre-#183 one, and should
    /// not be — that session was being read as "1 exercise, 1 working set,
    /// 0 kg" strength work.
    func testAHevyOnlyUserTurnIsUnchangedByTheDomainSplit() {
        let prompt = make([
            workout(daysAgo: 2, volume: 5_000, id: "w-1", title: "Push Day", loads: [
                MuscleLoad(group: .chest, volumeKg: 3_000, setCount: 9),
                MuscleLoad(group: .arms, volumeKg: 2_000, setCount: 6),
            ]),
            workout(daysAgo: 9, volume: 4_000, id: "w-2", title: "Pull Day", loads: [
                MuscleLoad(group: .back, volumeKg: 4_000, setCount: 12),
            ]),
        ])

        XCTAssertEqual(prompt.user, """
        Here is my own training data. Analyse it and tell me what to do next.

        ## Last 4 weeks (2025-05-19 to 2025-06-15)
        Sessions: 2
        Training days: 2 (0.5 days per week)
        Total volume: 9000 kg

        ## Volume per week
        - Week starting 2025-06-09 (most recent): 1 sessions, 5000 kg
        - Week starting 2025-06-02 (2 weeks back): 1 sessions, 4000 kg
        - Week starting 2025-05-26 (3 weeks back): 0 sessions, 0 kg
        - Week starting 2025-05-19 (4 weeks back): 0 sessions, 0 kg

        ## Muscle groups (last 4 weeks)
        - Back: 4000 kg (44% of volume), 12 working sets, trained in 1 session (0.3 per week)
        - Chest: 3000 kg (33% of volume), 9 working sets, trained in 1 session (0.3 per week)
        - Arms: 2000 kg (22% of volume), 6 working sets, trained in 1 session (0.3 per week)

        ## Previous 4 weeks (2025-04-21 to 2025-05-19), for comparison
        No workouts recorded. This may be a break, or simply the start of the recorded history \
        — do not assume which.

        ## Sessions (newest first)
        - 2025-06-13 Push Day: 5000 kg, 4 exercises, 12 working sets
        - 2025-06-06 Pull Day: 4000 kg, 4 exercises, 12 working sets

        ## Exercises (last 4 weeks)
        No exercise-level data is available for this window. Do not name exercises or weights.
        """)
    }

    /// The reviewer's probe: a sport whose sessions do not all carry a
    /// distance. Dividing the row's own totals would divide 10 km by 110 min
    /// and report 11:00 min/km for a runner holding 5:00, because the
    /// treadmill session's hour has no kilometres to go with it.
    func testMeanPaceIgnoresSessionsThatRecordedNoDistance() throws {
        let prompt = make([
            run(daysAgo: 1, id: "strava:1", meters: 10_000, seconds: 3_000),
            run(daysAgo: 2, id: "hevy-1", title: "Treadmill", source: .hevy, meters: nil, seconds: 3_600),
        ])
        let endurance = try section(prompt, "## Endurance, last 4 weeks")

        XCTAssertTrue(endurance.contains("mean pace 5:00 min/km"))
        XCTAssertFalse(endurance.contains("11:00"))
        // The totals still describe the sport truthfully — only the ratio
        // between them was never a pace.
        XCTAssertTrue(endurance.contains("Total distance: 10 km"))
        XCTAssertTrue(endurance.contains("Total time: 1 h 50 min"))
    }

    /// With no paired session at all the row falls back to the speed the
    /// source reported, rather than going silent about the pace.
    func testMeanPaceFallsBackToTheReportedSpeed() throws {
        let prompt = make([
            workout(
                daysAgo: 1,
                volume: 0,
                id: "strava:1",
                title: "Treadmill",
                source: .strava,
                kind: .run,
                durationSeconds: 3_600,
                cardio: CardioMetrics(averageSpeedMetersPerSecond: 3.125)
            ),
        ])
        let endurance = try section(prompt, "## Endurance, last 4 weeks")

        XCTAssertTrue(endurance.contains("mean pace 5:20 min/km"))
    }

    /// Ranking by distance alone hid every duration-only session as soon as
    /// one session carried a distance — a 2 h indoor ride is the longer effort
    /// and simply disappeared. Both are named when they are different
    /// sessions.
    func testTheLongestSessionByDistanceAndByTimeAreBothNamed() throws {
        let prompt = make([
            run(daysAgo: 1, id: "strava:1", meters: 10_000, seconds: 3_000),
            run(daysAgo: 2, id: "strava:2", title: "Indoor Ride", kind: .ride, meters: nil, seconds: 7_200),
        ])
        let endurance = try section(prompt, "## Endurance, last 4 weeks")

        XCTAssertTrue(endurance.contains("Longest session by distance: 10 km, 50 min on 2025-06-14 (Morning Run)"))
        XCTAssertTrue(endurance.contains("Longest session by time: 2 h on 2025-06-13 (Indoor Ride)"))
        XCTAssertFalse(endurance.contains("Longest session: "))
    }

    /// One line where one session is both, so the common case does not read as
    /// two findings.
    func testOneLongestSessionWhenDistanceAndTimeAgree() throws {
        let prompt = make([
            run(daysAgo: 1, id: "strava:1", meters: 10_000, seconds: 3_000),
            run(daysAgo: 2, id: "strava:2", title: "Evening Run", meters: 5_000, seconds: 1_500),
        ])
        let endurance = try section(prompt, "## Endurance, last 4 weeks")

        XCTAssertTrue(endurance.contains("Longest session: 10 km, 50 min on 2025-06-14 (Morning Run)"))
        XCTAssertFalse(endurance.contains("Longest session by"))
    }

    /// The reviewer's payload: a Strava `WeightTraining` session is strength
    /// work and belongs in these figures, but it arrives with no set data at
    /// all. Listed like a Hevy session it would claim twelve working sets
    /// nobody logged and a 0 kg total rule 5 invites the model to explain as
    /// bodyweight work — while its duration and heart rate appeared nowhere.
    func testASetlessStrengthSessionIsListedHonestlyWithWhatItsSourceRecorded() throws {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "hevy-1", title: "Push Day"),
            workout(
                daysAgo: 2,
                volume: 0,
                id: "strava:1",
                title: "Gym",
                source: .strava,
                kind: .strength,
                durationSeconds: 2_880,
                cardio: CardioMetrics(averageHeartRate: 132)
            ),
        ])
        let sessions = try section(prompt, "## Sessions (newest first)")

        XCTAssertTrue(sessions.contains(
            "- 2025-06-13 Gym: no sets logged (Strava records whole sessions), 48 min, mean heart rate 132 bpm"
        ))
        XCTAssertFalse(sessions.contains("Gym: 0 kg"))
        XCTAssertFalse(sessions.contains("Gym: no sets logged (Strava records whole sessions), 0 kg"))
        // The Hevy row is untouched.
        XCTAssertTrue(sessions.contains("- 2025-06-14 Push Day: 3000 kg, 4 exercises, 12 working sets"))
    }

    /// And the gap is stated next to the total it is missing from, so the
    /// count and the volume cannot read as a light week.
    func testTheWindowHeaderNamesTheSessionsThatLoggedNoSets() throws {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000, id: "hevy-1", title: "Push Day"),
            workout(daysAgo: 2, volume: 0, id: "strava:1", title: "Gym", source: .strava, kind: .strength),
        ])
        let header = try section(prompt, "## Last 4 weeks")

        XCTAssertTrue(header.contains("Sessions: 2"))
        XCTAssertTrue(header.contains("Total volume: 3000 kg"))
        XCTAssertTrue(header.contains(
            "Of these, 1 session logged no sets — their source records whole sessions, "
                + "so their load is not in the volume above."
        ))
    }

    /// Rule 5 has to say what a set-less row is, or the model explains the
    /// missing kilograms as bodyweight work — the very misreading the old
    /// source filter existed to prevent.
    func testSystemPromptExplainsASessionWithoutLoggedSets() {
        let system = AnalysisPromptBuilder.systemPrompt.lowercased()

        XCTAssertTrue(system.contains("a session listed as \"no sets logged\" recorded no set data at all"))
        XCTAssertTrue(system.contains("it is not bodyweight work"))
    }

    /// The coordinator's guard: rule 7 names heart rate as a load measure and
    /// rule 2 allows intensity-distribution principles, which together make
    /// "keep 80 % of your volume in zone 2" plausible — and a heart-rate zone
    /// is a population-derived norm (US-3 AC3).
    func testSystemPromptForbidsHeartRateZonesAndTargets() {
        let system = AnalysisPromptBuilder.systemPrompt.lowercased()

        XCTAssertTrue(system.contains("never name a heart-rate zone, a target heart rate, or a "
            + "percentage of maximum heart rate"))
        XCTAssertTrue(system.contains("derived from population norms"))
    }

    /// The same ban as a property of the user turn: the prompt must not hand
    /// the model a zone to reason with either.
    func testAMixedPromptNamesNoHeartRateZoneOrTarget() {
        let prompt = make([
            workout(daysAgo: 1, volume: 3_000),
            run(daysAgo: 2, id: "strava:1", heartRate: 150),
        ])

        for term in ["zone", "target heart rate", "max hr", "maximum heart rate", "% of max"] {
            XCTAssertFalse(prompt.user.lowercased().contains(term), "must not carry \(term)")
        }
    }

    /// A provider clock running fast, or a time zone the cache and the window
    /// disagree about, puts a session after `now` — "29 of 28 training days"
    /// and a negative rest count would be the prompt reporting an impossible
    /// week.
    func testTheWeekStructureClampsTrainingDaysToTheWindow() throws {
        let prompt = make(
            [workout(daysAgo: 1, volume: 3_000, id: "h1"), run(daysAgo: 2, id: "s1")]
                + (0..<8).map { run(daysAgo: -$0, id: "future-\($0)", title: "Future Run") },
            window: AnalysisWindow(weeks: 1)
        )
        let structure = try section(prompt, "## Week structure")

        XCTAssertTrue(structure.contains("Training days: 7 of 7"))
        XCTAssertTrue(structure.contains("Rest days: 0"))
        XCTAssertFalse(structure.contains("Rest days: -"))
    }

    // MARK: - Helpers

    private func make(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow = .default,
        profile: TrainingProfile = TrainingProfile(),
        analysisProfile: AnalysisProfile = .overallLoad
    ) -> AnalysisPrompt {
        AnalysisPromptBuilder.make(
            summaries: summaries,
            window: window,
            now: reference,
            calendar: calendar,
            profile: profile,
            analysisProfile: analysisProfile
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
        kind: ActivityKind = .strength,
        loads: [MuscleLoad] = [],
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil,
        cardio: CardioMetrics? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            title: title,
            // Midday, so a whole-day offset cannot land on a window boundary
            // and make the test depend on rounding rather than on the window.
            startTime: calendar.startOfDay(for: reference)
                .addingTimeInterval(Double(-daysAgo) * 86_400 + 43_200),
            source: source,
            kind: kind,
            volumeKg: volume,
            exerciseCount: 4,
            countedSetCount: 12,
            muscleLoads: loads,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            cardio: cardio
        )
    }

    /// An endurance session as a source delivers one: a mapped sport, no
    /// volume, distance and time on the session.
    private func run(
        daysAgo: Int,
        id: String = "strava:1",
        title: String = "Morning Run",
        source: ConnectorSource = .strava,
        kind: ActivityKind = .run,
        meters: Double? = 10_000,
        seconds: Int? = 3_000,
        heartRate: Int? = nil
    ) -> WorkoutSummary {
        workout(
            daysAgo: daysAgo,
            volume: 0,
            id: id,
            title: title,
            source: source,
            kind: kind,
            distanceMeters: meters,
            durationSeconds: seconds,
            cardio: heartRate.map { CardioMetrics(averageHeartRate: $0) }
        )
    }

    /// One "## " section of the user turn, header included.
    private func section(_ prompt: AnalysisPrompt, _ header: String) throws -> String {
        let range = try XCTUnwrap(prompt.user.range(of: header), "no \(header) section")
        let rest = prompt.user[range.lowerBound...]
        guard let next = rest.dropFirst().range(of: "\n\n## ") else { return String(rest) }
        return String(rest[..<next.lowerBound])
    }
}
