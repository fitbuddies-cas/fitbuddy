import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for the seam the result-screen UI test launches behind (#177).
final class MockAnalysisSeederTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.makeInMemory()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        container = nil
        try await super.tearDown()
    }

    func testWithoutTheArgumentNothingIsStored() async throws {
        await MockAnalysisSeeder.seedIfRequested(container: container, launchArguments: [], now: { self.reference })

        let stored = try await AnalysisResultStore(modelContainer: container).recent(limit: 5)
        XCTAssertTrue(stored.isEmpty)
    }

    /// The report survives the store, so the restored screen gets cards.
    func testTheArgumentStoresTheProgressReport() async throws {
        await MockAnalysisSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbSeedAnalysis"],
            now: { self.reference }
        )

        let stored = try await AnalysisResultStore(modelContainer: container).recent(limit: 5)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.report, AnalysisReportSamples.progress)
        XCTAssertEqual(stored.first?.provider, .claude)
        XCTAssertEqual(stored.first?.generatedAt, reference)
    }

    // MARK: - Report choice (#179)

    func testABareArgumentAsksForTheProgressReport() {
        XCTAssertEqual(MockAnalysisSeeder.requestedReport(in: ["-fbSeedAnalysis"]), AnalysisReportSamples.progress)
        XCTAssertEqual(
            MockAnalysisSeeder.requestedReport(in: ["-fbSeedAnalysis", "-fbResetState"]),
            AnalysisReportSamples.progress
        )
    }

    func testTheNameAfterTheArgumentPicksTheReport() {
        XCTAssertEqual(
            MockAnalysisSeeder.requestedReport(in: ["-fbSeedAnalysis", "progress"]),
            AnalysisReportSamples.progress
        )
        XCTAssertEqual(
            MockAnalysisSeeder.requestedReport(in: ["-fbSeedAnalysis", "recover"]),
            AnalysisReportSamples.recover
        )
        XCTAssertEqual(MockAnalysisSeeder.requestedReport(in: ["-fbSeedAnalysis", "hold"]), AnalysisReportSamples.hold)
        XCTAssertEqual(MockAnalysisSeeder.requestedReport(in: ["-fbSeedAnalysis", "thin"]), AnalysisReportSamples.thin)
        XCTAssertNil(MockAnalysisSeeder.requestedReport(in: []))
    }

    /// Every verdict can be seeded, so a UI test can open each headline.
    func testEveryVerdictHasASeedableReport() {
        XCTAssertEqual(
            Set(MockAnalysisSeeder.reports.values.map(\.verdict)),
            Set(AnalysisVerdict.allCases)
        )
    }

    func testTheRecoverArgumentStoresTheRecoveryReport() async throws {
        await MockAnalysisSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbSeedAnalysis", "recover"],
            now: { self.reference }
        )

        let stored = try await AnalysisResultStore(modelContainer: container).recent(limit: 5)
        XCTAssertEqual(stored.map(\.report), [AnalysisReportSamples.recover])
        XCTAssertEqual(stored.first?.context, AnalysisContext(sessionCount: 14, window: .default))
    }

    /// The thin report survives the store with its lead and without cards,
    /// so the restored screen opens the full analysis (#170).
    func testTheThinArgumentStoresTheReportWithoutCards() async throws {
        await MockAnalysisSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbSeedAnalysis", "thin"],
            now: { self.reference }
        )

        let stored = try await AnalysisResultStore(modelContainer: container).recent(limit: 5)
        XCTAssertEqual(stored.map(\.report), [AnalysisReportSamples.thin])
        XCTAssertEqual(stored.first?.report?.cards, [])
        XCTAssertEqual(stored.first?.report?.lead, AnalysisReportSamples.thin.lead)
        XCTAssertEqual(stored.first?.context, AnalysisContext(sessionCount: 2, window: .default), "Design 3.4b rests on 2 sessions")
    }

    /// A typo stores nothing rather than a report the test did not ask for.
    func testAnUnknownReportNameStoresNothing() async throws {
        await MockAnalysisSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbSeedAnalysis", "deload"],
            now: { self.reference }
        )

        let stored = try await AnalysisResultStore(modelContainer: container).recent(limit: 5)
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - The basis behind a seeded report (#188)

    /// Without a workout profile there is no cache to read, so the stored
    /// report keeps the fixed Hevy-only line it has had since #177.
    func testWithoutAProfileTheBasisStaysTheFixedLine() async throws {
        await MockAnalysisSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbSeedAnalysis", "overall"],
            now: { self.reference }
        )

        let stored = try await AnalysisResultStore(modelContainer: container).recent(limit: 1)
        let context = try XCTUnwrap(stored.first?.context)
        XCTAssertEqual(context.sessionCounts, [.hevy: MockAnalysisSeeder.defaultSessionCount])
    }

    /// Seeded beside a cross-source profile, the report rests on the window
    /// that profile actually cached — the line US-15 AC4 asks for, counted the
    /// way a real run counts it.
    func testWithAMixedProfileTheBasisNamesBothSources() async throws {
        let arguments = ["-fbSeedMockData", "mixed", "-fbSeedAnalysis", "overall"]
        await MockDataSeeder.seedIfRequested(
            container: container,
            launchArguments: arguments,
            timestamps: SyncTimestampStore(defaults: defaults),
            now: { self.reference }
        )

        await MockAnalysisSeeder.seedIfRequested(
            container: container,
            launchArguments: arguments,
            now: { self.reference }
        )

        let stored = try await AnalysisResultStore(modelContainer: container).recent(limit: 1)
        let context = try XCTUnwrap(stored.first?.context)
        XCTAssertEqual(context.countedSources, [.hevy, .strava])
        XCTAssertEqual(context.basisDescription, "12 Hevy · 12 Strava sessions")
        XCTAssertEqual(context.analysisProfile, .overallLoad)
        XCTAssertFalse(context.isThin)
    }

    /// The counting is the view model's own, so a seeded line and a live run's
    /// cannot drift apart.
    func testTheBasisIsCountedOverTheResolvedWindow() throws {
        let summaries = try MockWorkoutLoader(now: { self.reference })
            .workouts(for: .runner)
            .map(WorkoutSummary.init(workout:))

        let context = MockAnalysisSeeder.context(
            forReportNamed: "endurance",
            summaries: summaries,
            now: reference
        )

        XCTAssertEqual(context.countedSources, [.strava])
        XCTAssertEqual(context.domainCounts, [.endurance: 16])
        XCTAssertEqual(context.analysisProfile, .endurance)
        XCTAssertEqual(context.window, .default)
    }

    /// A second launch replaces the row rather than adding one, which would
    /// bring up the history link the test did not ask for.
    func testSeedingTwiceLeavesOneRow() async throws {
        for _ in 0..<2 {
            await MockAnalysisSeeder.seedIfRequested(
                container: container,
                launchArguments: ["-fbSeedAnalysis"],
                now: { self.reference }
            )
        }

        let stored = try await AnalysisResultStore(modelContainer: container).recent(limit: 5)
        XCTAssertEqual(stored.count, 1)
    }
}
