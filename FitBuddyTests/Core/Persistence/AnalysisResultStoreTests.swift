import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisResultStore` (#97) against a real in-memory
/// SwiftData container: the store's whole job is what SwiftData does with it,
/// so a double would test nothing.
final class AnalysisResultStoreTests: XCTestCase {
    private static let reference = Date(timeIntervalSince1970: 1_788_000_000)

    private var container: ModelContainer!
    private var sut: AnalysisResultStore!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.makeInMemory()
        sut = AnalysisResultStore(modelContainer: container)
    }

    override func tearDown() async throws {
        sut = nil
        container = nil
        try await super.tearDown()
    }

    func testLatestIsNilBeforeAnyAnalysisWasSaved() async throws {
        let stored = try await sut.latest()

        XCTAssertNil(stored)
    }

    func testSavedAnalysisIsReadBackWithItsTimestampAndWindow() async throws {
        try await sut.save(
            text: "Add 2.5 kg on bench next session.",
            generatedAt: Self.reference,
            context: Self.context(sessions: 6, weeks: 8)
        )

        let latest = try await sut.latest()
        let stored = try XCTUnwrap(latest)
        XCTAssertEqual(stored.text, "Add 2.5 kg on bench next session.")
        XCTAssertEqual(stored.generatedAt, Self.reference)
        // The widened window and its session count travel with the text (#87,
        // #36) — a restored screen that silently claimed four weeks, or
        // re-counted today's cache, would misdescribe the advice.
        XCTAssertEqual(stored.context, Self.context(sessions: 6, weeks: 8))
    }

    /// Only the last recommendation is kept — v0 has no history screen, and a
    /// second row would leave `latest()` picking between two.
    func testSavingReplacesThePreviousAnalysis() async throws {
        try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())
        try await sut.save(
            text: "Second",
            generatedAt: Self.reference.addingTimeInterval(7 * 3_600),
            context: Self.context()
        )

        let stored = try await sut.latest()
        let context = ModelContext(container)
        XCTAssertEqual(stored?.text, "Second")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AnalysisResult>()), 1)
    }

    func testDeleteAllRemovesTheStoredAnalysis() async throws {
        try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())

        try await sut.deleteAll()

        let stored = try await sut.latest()
        XCTAssertNil(stored)
    }

    func testDeleteAllOnAnEmptyStoreSucceeds() async throws {
        try await sut.deleteAll()

        let stored = try await sut.latest()
        XCTAssertNil(stored)
    }

    /// The wiring the app actually runs: `RootView` builds one store for the
    /// analysis screen and a second for the settings screen, `HevyService` a
    /// third — three `@ModelActor`s with three own `ModelContext`s over one
    /// container. A delete on one has to be visible to the others, otherwise
    /// "Hevy key replaced → recommendation dropped → sheet opens" would restore
    /// the discarded account's advice from a stale context.
    func testADeleteOnOneStoreIsVisibleToAnother() async throws {
        let other = AnalysisResultStore(modelContainer: container)
        try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())

        try await other.deleteAll()

        let stored = try await sut.latest()
        XCTAssertNil(stored)
    }

    private static func context(sessions: Int = 12, weeks: Int = 4) -> AnalysisContext {
        AnalysisContext(sessionCount: sessions, window: AnalysisWindow(weeks: weeks))
    }
}
