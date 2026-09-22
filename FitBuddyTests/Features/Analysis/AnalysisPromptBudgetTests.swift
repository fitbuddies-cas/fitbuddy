import XCTest
@testable import FitBuddy

/// Unit tests for the prompt token budget and its degradation ladder
/// (TD-1, US-15 AC8, #187).
///
/// Two halves. The first asserts that the prompt the app can actually build —
/// 13 weeks of strength *and* endurance, forty movements, the widest rung of
/// the window ladder — stays well inside the budget without giving anything
/// up. The second drives the ladder with a deliberately small `budgetTokens`,
/// because the alternative is a fixture built to be enormous, which would test
/// the fixture rather than the rungs.
final class AnalysisPromptBudgetTests: XCTestCase {
    private var calendar: Calendar!
    /// 2025-06-15 12:26:40 UTC.
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    }

    // MARK: - The constant

    /// The budget is derived from the smallest of the three context windows,
    /// which is what the comment on it claims — a later edit that raises the
    /// share has to move this number too.
    func testTheBudgetIsAShareOfTheSmallestProviderContextWindow() {
        XCTAssertEqual(AnalysisPromptBudget.smallestContextWindowTokens, 128_000)
        XCTAssertEqual(
            AnalysisPromptBudget.maxPromptTokens,
            AnalysisPromptBudget.smallestContextWindowTokens / 16
        )
        XCTAssertEqual(AnalysisPromptBudget.maxPromptTokens, 8_000)
    }

    /// Characters over four, rounded up: an empty string costs nothing and a
    /// single character costs a token, so no prompt is ever estimated at zero.
    func testTheTokenEstimateRoundsUp() {
        XCTAssertEqual(AnalysisPromptBudget.estimatedTokens(in: ""), 0)
        XCTAssertEqual(AnalysisPromptBudget.estimatedTokens(in: "a"), 1)
        XCTAssertEqual(AnalysisPromptBudget.estimatedTokens(in: "abcd"), 1)
        XCTAssertEqual(AnalysisPromptBudget.estimatedTokens(in: "abcde"), 2)
        XCTAssertEqual(AnalysisPromptBudget.estimatedTokens(in: String(repeating: "x", count: 4_000)), 1_000)
    }

    func testTheEstimateOfAPromptIsTheSumOfItsTurns() {
        let prompt = AnalysisPrompt(system: String(repeating: "s", count: 400), user: String(repeating: "u", count: 800))

        XCTAssertEqual(AnalysisPromptBudget.estimatedTokens(of: prompt), 300)
        XCTAssertTrue(AnalysisPromptBudget.fits(prompt))
    }

    // MARK: - AC8: the worst case the app can build

    /// 90 days of strength *and* cardio in the cache — the criterion itself.
    /// The window resolves to the widest rung of #87's ladder, both domains
    /// render every section, and the prompt still fits with nothing given up.
    func testNinetyDaysOfStrengthAndCardioStayUnderTheBudget() {
        let cache = WorstCase(calendar: calendar, reference: reference)

        let prompt = make(cache)

        XCTAssertTrue(
            AnalysisPromptBudget.fits(prompt),
            "\(AnalysisPromptBudget.estimatedTokens(of: prompt)) estimated tokens"
        )
        XCTAssertTrue(prompt.detail.isFull, "the worst case must not need the ladder")
        // Both domains are in it, so this really is the mixed prompt and not a
        // strength-only one that happens to be short.
        XCTAssertTrue(prompt.user.contains("## Volume per week"))
        XCTAssertTrue(prompt.user.contains("## Endurance per week"))
        XCTAssertTrue(prompt.user.contains("## Week structure"))
        XCTAssertTrue(prompt.user.contains("## Exercises (last 13 weeks)"))
    }

    /// Room to spare, not a near miss: the worst case has to leave enough
    /// headroom that a cache of unusually long session and exercise titles
    /// still fits, which is the only thing the ladder exists for.
    ///
    /// Two thirds rather than a half, because the budget was set at roughly
    /// twice this prompt on purpose — the figure is around 4 050 estimated
    /// tokens, and a test pinning it any tighter would fail on a reworded
    /// section rather than on a prompt that grew.
    func testTheWorstCaseLeavesHeadroom() {
        let estimate = AnalysisPromptBudget.estimatedTokens(of: make(WorstCase(calendar: calendar, reference: reference)))

        XCTAssertLessThan(estimate, AnalysisPromptBudget.maxPromptTokens * 2 / 3)
    }

    /// The three profiles differ in bulk (AC1, #185) and none of them is the
    /// one that breaks the budget — which is why one constant, measured
    /// against the prompt that was built, needs no per-profile table.
    func testEveryProfileOfTheWorstCaseFitsWithoutDegrading() {
        let cache = WorstCase(calendar: calendar, reference: reference)

        for analysisProfile in AnalysisProfile.allCases {
            let prompt = make(cache, analysisProfile: analysisProfile)

            XCTAssertTrue(AnalysisPromptBudget.fits(prompt), analysisProfile.rawValue)
            XCTAssertTrue(prompt.detail.isFull, analysisProfile.rawValue)
        }
    }

    // MARK: - The ladder

    /// Rung 1 — #187's step 2. The session list drops to 20 and the footer
    /// #173 established says how many rows are missing and why.
    func testATightBudgetCapsTheStrengthSessionList() throws {
        let cache = WorstCase(calendar: calendar, reference: reference)

        let prompt = make(cache, budgetTokens: rungBudget(cache, rung: 1))

        XCTAssertEqual(prompt.detail.listedSessions, 20)
        XCTAssertEqual(prompt.detail.listedExercises, AnalysisPromptBuilder.maxListedExercises)
        let sessions = try section(prompt, "## Sessions (newest first)")
        XCTAssertEqual(sessions.components(separatedBy: "\n- ").count - 1, 20)
        XCTAssertTrue(sessions.contains("older sessions in this window omitted"))
    }

    /// Rung 2 — #187's step 3. The Exercises section drops to six, and its
    /// footer counts the movements the window holds beyond them.
    func testATighterBudgetAlsoCapsTheExerciseSection() throws {
        let cache = WorstCase(calendar: calendar, reference: reference)

        let prompt = make(cache, budgetTokens: rungBudget(cache, rung: 2))

        XCTAssertEqual(prompt.detail.listedExercises, 6)
        let exercises = try section(prompt, "## Exercises")
        XCTAssertEqual(exercises.components(separatedBy: "\n- ").count - 1, 6)
        XCTAssertTrue(exercises.contains("(6 exercises with the most volume listed; 34 more in this window omitted)"))
    }

    /// Rung 3 — this ladder's own step, for the long list the issue's four
    /// could not reach: a widened window renders thirteen per-week rows in
    /// each domain.
    func testTheTightestBudgetAlsoCapsThePerWeekRowsOfBothDomains() throws {
        let cache = WorstCase(calendar: calendar, reference: reference)

        let prompt = make(cache, budgetTokens: rungBudget(cache, rung: 3))

        XCTAssertEqual(prompt.detail.listedWeeks, 4)
        for header in ["## Volume per week", "## Endurance per week"] {
            let weeks = try section(prompt, header)
            XCTAssertEqual(weeks.components(separatedBy: "\n- Week starting ").count - 1, 4, header)
            XCTAssertTrue(weeks.contains("Weeks without sessions are not listed"), header)
            XCTAssertTrue(weeks.contains("9 earlier ones omitted"), header)
            XCTAssertTrue(weeks.contains("the totals above cover all 13 weeks"), header)
        }
    }

    /// The trap rung 3 walked into on its first version: a window is only
    /// widened *because* the last four weeks hold nothing (#87), so "the four
    /// most recent weeks" is precisely the four empty ones. The rows follow
    /// the training, not the calendar.
    func testTheWeekRowsFollowTheTrainingAndNotTheCalendar() throws {
        // Nothing in the last four weeks, nine weeks of training before them —
        // the shape `AnalysisWindow.resolve` actually produces.
        let cache = WorstCase(calendar: calendar, reference: reference, firstTrainingDaysAgo: 57)
        let window = try XCTUnwrap(
            AnalysisWindow.resolve(for: cache.summaries, endingAt: reference, calendar: calendar)
        )
        XCTAssertEqual(window.weeks, 13, "the fixture has to widen the window or it tests nothing")

        let prompt = make(cache, window: window, budgetTokens: rungBudget(cache, window: window, rung: 3))

        XCTAssertEqual(prompt.detail.listedWeeks, 4)
        for header in ["## Volume per week", "## Endurance per week"] {
            let weeks = try section(prompt, header)
            XCTAssertEqual(weeks.components(separatedBy: "\n- Week starting ").count - 1, 4, header)
            // Weeks 0-3 recorded nothing and are gone; the newest week that
            // did — index 4, "5 weeks back" — leads the list.
            XCTAssertFalse(weeks.contains("(most recent)"), header)
            XCTAssertTrue(weeks.contains("(9 weeks back)"), header)
            XCTAssertTrue(weeks.contains("(12 weeks back)"), header)
            XCTAssertFalse(weeks.contains(": 0 sessions"), header)
            XCTAssertTrue(weeks.contains("Weeks without sessions are not listed"), header)
        }
    }

    /// The ladder at the **real** budget, not an injected one: a cache whose
    /// sessions and movements carry pathologically long titles is what a
    /// 13-week window of both domains needs before 8 000 tokens bind. The
    /// prompt that goes out is smaller than full and inside the budget.
    func testAWindowOfVeryLongTitlesDegradesAtTheRealBudget() {
        let cache = WorstCase(calendar: calendar, reference: reference, titlePadding: 600)

        let prompt = make(cache)

        XCTAssertFalse(prompt.detail.isFull, "the real budget has to bind here")
        XCTAssertTrue(
            AnalysisPromptBudget.fits(prompt),
            "\(AnalysisPromptBudget.estimatedTokens(of: prompt)) estimated tokens"
        )
        XCTAssertTrue(prompt.user.contains("in this window omitted"), "the cut has to name itself")
    }

    /// A rung only ever gives up list rows. Every aggregate the recommendation
    /// and the report validation rest on — the window totals, the muscle
    /// split, the endurance headline figures, the last seven days — is the
    /// same string at every rung.
    func testTheAggregatesAreTheSameAtEveryRung() throws {
        let cache = WorstCase(calendar: calendar, reference: reference)
        let full = make(cache)
        let trimmed = make(cache, budgetTokens: rungBudget(cache, rung: 3))

        XCTAssertNotEqual(full.user, trimmed.user)
        for header in [
            "## Last 13 weeks",
            "## Muscle groups",
            "## Previous 13 weeks",
            "## Endurance, last 13 weeks",
            "## Week structure",
        ] {
            XCTAssertEqual(try section(full, header), try section(trimmed, header), header)
        }
    }

    /// The ladder ends; the analysis does not. A budget nothing can satisfy
    /// sends the last rung rather than an empty or refused prompt — the app
    /// gives up rows, never the run.
    func testABudgetNoRungCanMeetStillProducesTheLastRung() {
        let cache = WorstCase(calendar: calendar, reference: reference)

        let prompt = make(cache, budgetTokens: 1)

        XCTAssertEqual(prompt.detail, AnalysisPromptDetail.ladder[AnalysisPromptDetail.ladder.count - 1])
        XCTAssertFalse(prompt.user.isEmpty)
        XCTAssertTrue(prompt.user.contains("## Last 13 weeks"))
    }

    // MARK: - AC: the Hevy-only prompt is untouched

    /// Four weeks of Hevy — the prompt #183 froze — is nowhere near the
    /// budget, so the ladder never touches it: the user turn is byte for byte
    /// the one an unbounded builder produces.
    func testAFourWeekHevyWindowIsUnchangedByTheBudget() {
        let summaries = (0..<12).map { index in
            workout(daysAgo: index * 2, volume: 4_200, id: "hevy:\(index)")
        }
        let budgeted = AnalysisPromptBuilder.make(
            summaries: summaries,
            window: .default,
            now: reference,
            calendar: calendar
        )
        let unbounded = AnalysisPromptBuilder.make(
            summaries: summaries,
            window: .default,
            now: reference,
            calendar: calendar,
            budgetTokens: .max
        )

        XCTAssertEqual(budgeted.user, unbounded.user)
        XCTAssertTrue(budgeted.detail.isFull)
        XCTAssertFalse(budgeted.user.contains("omitted"))
    }

    // MARK: - The validator anchors on what the prompt still carries

    /// The rule the budget must not break: a card is checked against the data
    /// the model was shown. A prompt trimmed to six exercises hands the
    /// validation six, and the six are exactly the ones its section lists.
    func testTheValidationSeesOnlyTheExercisesTheTrimmedPromptLists() {
        let cache = WorstCase(calendar: calendar, reference: reference)
        let prompt = make(cache, budgetTokens: rungBudget(cache, rung: 2))

        let evidence = AnalysisReportEvidence(
            summaries: cache.summaries,
            exercises: cache.exercises,
            progressions: cache.progressions,
            details: [],
            window: .widest,
            now: reference,
            calendar: calendar,
            promptDetail: prompt.detail
        )

        XCTAssertEqual(evidence.exercises.count, 6)
        for exercise in evidence.exercises {
            XCTAssertTrue(prompt.user.contains(exercise.title), exercise.title)
        }
    }

    /// The other side of it: a progression card naming a movement the trimmed
    /// prompt no longer lists is not backed by the cache any more, and is
    /// downgraded exactly as an invented exercise is.
    func testAProgressionCardOnATrimmedAwayExerciseIsNotValidated() {
        let cache = WorstCase(calendar: calendar, reference: reference)
        let prompt = make(cache, budgetTokens: rungBudget(cache, rung: 2))
        let dropped = cache.exercises[8]
        XCTAssertFalse(prompt.user.contains(dropped.title))

        let report = AnalysisReport(
            headline: "Add load",
            verdict: .progress,
            lead: "One step up.",
            cards: [
                .progression(
                    exercise: dropped.title,
                    muscleGroup: dropped.muscleGroup.displayName,
                    fromKg: 87.5,
                    toKg: 90,
                    reasoning: "Steady reps at the current weight."
                ),
            ],
            summary: "A step on a movement the prompt no longer lists."
        )
        func validated(at detail: AnalysisPromptDetail) -> ValidatedAnalysisReport {
            AnalysisReportValidator.validate(
                report,
                against: AnalysisReportEvidence(
                    summaries: cache.summaries,
                    exercises: cache.exercises,
                    progressions: cache.progressions,
                    details: [],
                    window: .widest,
                    now: reference,
                    calendar: calendar,
                    promptDetail: detail
                )
            )
        }
        func hasProgression(_ report: ValidatedAnalysisReport) -> Bool {
            report.cards.contains { if case .progression = $0 { return true } else { return false } }
        }

        // The card itself is sound — at the full rung the same report keeps
        // it, so what removes it below is the trim and nothing else.
        XCTAssertTrue(hasProgression(validated(at: .full)))
        XCTAssertFalse(
            hasProgression(validated(at: prompt.detail)),
            "a card the trimmed prompt gave no exercise for must not survive"
        )
    }

    // MARK: - Helpers

    private func make(
        _ cache: WorstCase,
        window: AnalysisWindow = .widest,
        analysisProfile: AnalysisProfile = .overallLoad,
        budgetTokens: Int = AnalysisPromptBudget.maxPromptTokens
    ) -> AnalysisPrompt {
        AnalysisPromptBuilder.make(
            summaries: cache.summaries,
            exercises: cache.exercises,
            progressions: cache.progressions,
            window: window,
            now: reference,
            calendar: calendar,
            analysisProfile: analysisProfile,
            budgetTokens: budgetTokens
        )
    }

    /// A budget the given rung is the first to satisfy: one token under what
    /// the rung before it needs.
    ///
    /// Derived from the prompt rather than hard-coded, so a reworded section
    /// moves the threshold with it instead of failing a test about the ladder
    /// for a reason that has nothing to do with it.
    private func rungBudget(_ cache: WorstCase, window: AnalysisWindow = .widest, rung: Int) -> Int {
        // `.max` always returns the first rung, so walk down from it by
        // rebuilding with a budget one token below what each rung produced.
        var budget = AnalysisPromptBudget.estimatedTokens(
            of: make(cache, window: window, budgetTokens: .max)
        ) - 1
        for _ in 0..<max(0, rung - 1) {
            let step = make(cache, window: window, budgetTokens: budget)
            budget = AnalysisPromptBudget.estimatedTokens(of: step) - 1
        }
        return budget
    }

    /// One "## " section of the user turn, header included.
    private func section(_ prompt: AnalysisPrompt, _ header: String) throws -> String {
        let range = try XCTUnwrap(prompt.user.range(of: header), "no \(header) section")
        let rest = prompt.user[range.lowerBound...]
        guard let next = rest.dropFirst().range(of: "\n\n## ") else { return String(rest) }
        return String(rest[..<next.lowerBound])
    }

    private func workout(daysAgo: Int, volume: Double, id: String) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            title: "Session",
            startTime: calendar.startOfDay(for: reference)
                .addingTimeInterval(Double(-daysAgo) * 86_400 + 43_200),
            source: .hevy,
            kind: .strength,
            volumeKg: volume,
            exerciseCount: 4,
            countedSetCount: 12,
            muscleLoads: [MuscleLoad(group: .chest, volumeKg: volume, setCount: 12)]
        )
    }

    // MARK: - Fixture

    /// The largest cache the app can analyse: 13 weeks plus an equally long
    /// comparison window, four strength sessions and four endurance sessions a
    /// week, every muscle group loaded, forty movements with a full
    /// progression each. Titles are the length a real Hevy or Strava session
    /// carries unless `titlePadding` says otherwise.
    ///
    /// By default it trains in the last four weeks too, which
    /// `AnalysisWindow.resolve` would answer with the 4-week rung — the
    /// fixture is passed `.widest` on purpose, because what it is for is the
    /// *largest prompt the builder can be made to produce*, not a window the
    /// ladder would pick. `firstTrainingDaysAgo` is how a test asks for the
    /// shape `resolve` really produces: a gap at the recent end.
    private struct WorstCase {
        let summaries: [WorkoutSummary]
        let exercises: [ExerciseSummary]
        let progressions: [String: ExerciseProgression]

        /// - Parameters:
        ///   - firstTrainingDaysAgo: The most recent day that carries a
        ///     session. 0 — the default — trains right up to the reference day.
        ///   - titlePadding: Extra characters on every session and exercise
        ///     title, for the one test that has to make the real budget bind.
        init(
            calendar: Calendar,
            reference: Date,
            firstTrainingDaysAgo: Int = 0,
            titlePadding: Int = 0
        ) {
            let midnight = calendar.startOfDay(for: reference)
            func day(_ daysAgo: Int) -> Date {
                midnight.addingTimeInterval(Double(-daysAgo) * 86_400 + 43_200)
            }
            let padding = titlePadding > 0 ? " " + String(repeating: "x", count: titlePadding) : ""
            let groups = MuscleGroup.allCases
            let sports: [ActivityKind] = [.run, .ride, .swim, .hike]
            var summaries: [WorkoutSummary] = []
            // 26 weeks: the widest window of the ladder and its comparison
            // window, so every section of the prompt is filled.
            for dayIndex in firstTrainingDaysAgo..<(26 * 7) {
                if dayIndex % 7 < 4 {
                    summaries.append(
                        WorkoutSummary(
                            id: "hevy:\(dayIndex)",
                            title: "Upper Body Strength — Push Focus\(padding)",
                            startTime: day(dayIndex),
                            source: .hevy,
                            kind: .strength,
                            volumeKg: 8_450,
                            exerciseCount: 7,
                            countedSetCount: 24,
                            muscleLoads: groups.map {
                                MuscleLoad(group: $0, volumeKg: 1_200, setCount: 6)
                            },
                            durationSeconds: 4_800
                        )
                    )
                }
                if dayIndex % 7 >= 3 {
                    summaries.append(
                        WorkoutSummary(
                            id: "strava:\(dayIndex)",
                            title: "Evening Trail Run in the Jura\(padding)",
                            startTime: day(dayIndex).addingTimeInterval(7_200),
                            source: .strava,
                            kind: sports[dayIndex % sports.count],
                            volumeKg: 0,
                            exerciseCount: 0,
                            countedSetCount: 0,
                            distanceMeters: 12_340,
                            durationSeconds: 3_845,
                            cardio: CardioMetrics(
                                averageHeartRate: 148,
                                maxHeartRate: 176,
                                elevationGainMeters: 340,
                                averageSpeedMetersPerSecond: 3.2
                            )
                        )
                    )
                }
            }
            self.summaries = summaries

            var exercises: [ExerciseSummary] = []
            var progressions: [String: ExerciseProgression] = [:]
            for index in 0..<40 {
                let id = "ex-\(index)"
                let summary = ExerciseSummary(
                    id: id,
                    title: "Incline Bench Press (Barbell) \(index)\(padding)",
                    muscleGroup: groups[index % groups.count],
                    sessionCount: 12,
                    countedSetCount: 36,
                    volumeKg: Double(9_000 - index * 100),
                    lastPerformed: day(firstTrainingDaysAgo + index % 7)
                )
                exercises.append(summary)
                progressions[id] = ExerciseProgression(
                    id: id,
                    title: summary.title,
                    // The same gap the sessions have, so the fixture does
                    // not claim a movement on a day it recorded no workout.
                    sessions: (0..<12).map { 89 - $0 * 7 }
                        .filter { $0 >= firstTrainingDaysAgo }
                        .enumerated()
                        .map { position, daysAgo in
                        ExerciseHistoryEntry(
                            workoutID: "hevy:\(daysAgo)",
                            sessionStart: day(daysAgo),
                            sets: (0..<3).map {
                                SetDetail(
                                    index: $0,
                                    type: .normal,
                                    // Oldest first, so the newest session is
                                    // the heaviest and the trend rises.
                                    weightKg: 60 + Double(position) * 2.5,
                                    reps: 8,
                                    distanceMeters: nil,
                                    durationSeconds: nil,
                                    rpe: 8
                                )
                            }
                        )
                    }
                )
            }
            self.exercises = exercises
            self.progressions = progressions
        }
    }
}
