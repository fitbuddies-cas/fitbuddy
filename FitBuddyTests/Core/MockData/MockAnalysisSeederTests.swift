import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for the seam the result-screen UI test launches behind (#177).
final class MockAnalysisSeederTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.makeInMemory()
    }

    override func tearDown() async throws {
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
