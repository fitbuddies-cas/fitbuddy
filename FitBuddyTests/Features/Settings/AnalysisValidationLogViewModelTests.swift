import XCTest
@testable import FitBuddy

// Developer tooling: excluded from Release builds, so the validation log
// view never ships in a TestFlight binary. The log itself is captured and
// stored in every build (#228).
#if DEBUG

/// `AnalysisValidationLogViewModel` and `AnalysisValidationTally` (#228): the
/// developer view lists every stored log and counts the interventions across
/// them, keeping analyses without a log apart from clean ones.
@MainActor
final class AnalysisValidationLogViewModelTests: XCTestCase {
    private static let reference = Date(timeIntervalSince1970: 1_788_000_000)

    private static let overridden = AnalysisValidationLog(
        provider: .claude,
        model: "claude-opus-5",
        modelVerdict: .progress,
        appVerdict: .hold,
        verdictReason: .noNewBest,
        interventions: [
            AnalysisIntervention(
                subject: .progression,
                action: .downgraded,
                reason: .aboveRange,
                figure: AnalysisInterventionFigure(proposed: 70, app: 60, allowed: 62.5...65, unit: .kilograms)
            ),
            AnalysisIntervention(subject: .verdict, action: .replaced, reason: .verdictOverridden),
        ]
    )

    private static let rejectedTwice = AnalysisValidationLog(
        provider: .mistral,
        model: "mistral-medium-3-5",
        modelVerdict: .hold,
        appVerdict: .hold,
        verdictReason: .plateauMajority,
        interventions: [
            AnalysisIntervention(subject: .progression, action: .downgraded, reason: .aboveRange),
            AnalysisIntervention(subject: .note, action: .dropped, reason: .overCardLimit),
        ]
    )

    private static let clean = AnalysisValidationLog(
        provider: .gemini,
        model: "gemini-3.6-flash",
        modelVerdict: .hold,
        appVerdict: .hold,
        verdictReason: .noNewBest,
        interventions: []
    )

    // MARK: - Load

    func testListsEveryStoredLogNewestFirstAndCountsTheRest() async {
        let store = StubAnalysisResultStore(entries: [
            snapshot(minutesAgo: 0, log: Self.overridden),
            snapshot(minutesAgo: 1, log: nil),
            snapshot(minutesAgo: 2, log: Self.clean),
        ])
        let sut = AnalysisValidationLogViewModel(store: store)

        await sut.load()

        XCTAssertTrue(sut.isLoaded)
        XCTAssertNil(sut.failure)
        XCTAssertEqual(sut.entries.map(\.log), [Self.overridden, Self.clean])
        XCTAssertEqual(sut.unrecordedCount, 1, "A prose row is not a clean run")
        XCTAssertEqual(sut.tally.runs, 2)
        XCTAssertEqual(sut.tally.cleanRuns, 1)
    }

    func testAnEmptyStoreHasAnEmptyTally() async {
        let sut = AnalysisValidationLogViewModel(store: StubAnalysisResultStore())

        await sut.load()

        XCTAssertEqual(sut.entries, [])
        XCTAssertEqual(sut.tally, AnalysisValidationTally(logs: []))
        XCTAssertEqual(sut.tally.rows, [])
    }

    func testAnUnreadableStoreNamesTheFailure() async {
        let store = StubAnalysisResultStore(entries: [snapshot(minutesAgo: 0, log: Self.clean)])
        await store.setReadFails(true)
        let sut = AnalysisValidationLogViewModel(store: store)

        await sut.load()

        XCTAssertTrue(sut.isLoaded)
        XCTAssertNotNil(sut.failure)
        XCTAssertEqual(sut.entries, [])
    }

    // MARK: - Tally

    func testTheTallyCountsEachPartAndReasonAcrossRuns() {
        let tally = AnalysisValidationTally(logs: [Self.overridden, Self.rejectedTwice, Self.clean])

        XCTAssertEqual(tally.runs, 3)
        XCTAssertEqual(tally.cleanRuns, 1)
        XCTAssertEqual(tally.overriddenVerdicts, 1)
        XCTAssertEqual(tally.rows, [
            AnalysisValidationTallyRow(subject: .progression, reason: .aboveRange, count: 2),
            AnalysisValidationTallyRow(subject: .note, reason: .overCardLimit, count: 1),
            AnalysisValidationTallyRow(subject: .verdict, reason: .verdictOverridden, count: 1),
        ])
    }

    // MARK: - Formatting

    func testTheSourceNamesProviderAndModel() {
        XCTAssertEqual(AnalysisValidationLogViewModel.source(of: Self.overridden), "Claude · claude-opus-5")
        let anonymous = AnalysisValidationLog(
            modelVerdict: .hold, appVerdict: .hold, verdictReason: .noNewBest, interventions: []
        )
        XCTAssertEqual(AnalysisValidationLogViewModel.source(of: anonymous), "Unknown provider")
    }

    func testTheVerdictLineShowsTheOverrideOnlyWhereThereWasOne() {
        XCTAssertEqual(AnalysisValidationLogViewModel.verdictLine(of: Self.overridden), "progress → hold (noNewBest)")
        XCTAssertEqual(AnalysisValidationLogViewModel.verdictLine(of: Self.clean), "hold (noNewBest)")
    }

    func testAnInterventionReadsAsPartActionAndReasonWithItsFigures() {
        let intervention = Self.overridden.interventions[0]

        XCTAssertEqual(AnalysisValidationLogViewModel.title(of: intervention), "progression downgraded: aboveRange")
        XCTAssertEqual(
            AnalysisValidationLogViewModel.figureLine(of: intervention),
            "proposed 70 kg · app 60 kg · allowed 62.5–65 kg"
        )
        XCTAssertNil(AnalysisValidationLogViewModel.figureLine(of: Self.overridden.interventions[1]))
    }

    // MARK: - Helpers

    private func snapshot(minutesAgo: Double, log: AnalysisValidationLog?) -> AnalysisResultSnapshot {
        AnalysisResultSnapshot(
            id: UUID(),
            text: "Summary",
            generatedAt: Self.reference.addingTimeInterval(-minutesAgo * 60),
            context: AnalysisContext(sessionCount: 12, window: .default),
            report: AnalysisReportFactory.validated(.hold),
            provider: log?.provider,
            validationLog: log
        )
    }
}

#endif
