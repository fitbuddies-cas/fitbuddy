import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisResultStore` (#97, #117) against a real in-memory
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

    /// The user paid a provider for every one of these texts, so a new run
    /// adds to them instead of replacing the last one (#117).
    func testSavingKeepsThePreviousAnalysis() async throws {
        try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())
        try await sut.save(
            text: "Second",
            generatedAt: Self.reference.addingTimeInterval(7 * 3_600),
            context: Self.context()
        )

        let stored = try await sut.latest()
        let context = ModelContext(container)
        XCTAssertEqual(stored?.text, "Second")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AnalysisResult>()), 2)
    }

    func testSaveReturnsTheIdentityOfTheRowItWrote() async throws {
        let id = try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())

        let stored = try await sut.latest()
        XCTAssertEqual(stored?.id, id)
    }

    // MARK: - History (US-3 AC11)

    func testRecentReturnsTheAnalysesNewestFirst() async throws {
        for index in 0..<3 {
            try await sut.save(
                text: "Analysis \(index)",
                generatedAt: Self.reference.addingTimeInterval(Double(index) * 3_600),
                context: Self.context()
            )
        }

        let recent = try await sut.recent(limit: 10)

        XCTAssertEqual(recent.map(\.text), ["Analysis 2", "Analysis 1", "Analysis 0"])
    }

    func testRecentIsEmptyBeforeAnyAnalysisWasSaved() async throws {
        let recent = try await sut.recent(limit: 10)

        XCTAssertTrue(recent.isEmpty)
    }

    func testRecentHonoursItsLimit() async throws {
        for index in 0..<5 {
            try await sut.save(
                text: "Analysis \(index)",
                generatedAt: Self.reference.addingTimeInterval(Double(index) * 3_600),
                context: Self.context()
            )
        }

        let recent = try await sut.recent(limit: 2)

        XCTAssertEqual(recent.map(\.text), ["Analysis 4", "Analysis 3"])
    }

    /// The cap is what keeps the device from accumulating health-derived text
    /// nobody ever scrolls back to.
    func testTheStoreNeverHoldsMoreThanTwentyAnalyses() async throws {
        for index in 0..<(AnalysisHistoryLimit.rows + 5) {
            try await sut.save(
                text: "Analysis \(index)",
                generatedAt: Self.reference.addingTimeInterval(Double(index) * 3_600),
                context: Self.context()
            )
        }

        let context = ModelContext(container)
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<AnalysisResult>()),
            AnalysisHistoryLimit.rows
        )
        // The newest survive the trim, the oldest are the ones dropped.
        let recent = try await sut.recent(limit: AnalysisHistoryLimit.rows)
        XCTAssertEqual(recent.first?.text, "Analysis 24")
        XCTAssertEqual(recent.last?.text, "Analysis 5")
    }

    func testDeleteRemovesOnlyTheNamedAnalysis() async throws {
        let first = try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())
        try await sut.save(
            text: "Second",
            generatedAt: Self.reference.addingTimeInterval(3_600),
            context: Self.context()
        )

        try await sut.delete(id: first)

        let recent = try await sut.recent(limit: 10)
        XCTAssertEqual(recent.map(\.text), ["Second"])
    }

    /// Two screens can hold the same list, so the second delete has nothing
    /// left to do — and must not fail over it.
    func testDeletingAnUnknownIdIsNotAnError() async throws {
        try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())

        try await sut.delete(id: UUID())

        let recent = try await sut.recent(limit: 10)
        XCTAssertEqual(recent.count, 1)
    }

    // MARK: - Feedback per analysis (US-3 AC9)

    func testAnalysesStartWithoutAVerdict() async throws {
        try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())

        let stored = try await sut.latest()
        XCTAssertNil(stored?.feedback)
    }

    func testFeedbackIsStoredOnTheAnalysisItWasGivenOn() async throws {
        let first = try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())
        try await sut.save(
            text: "Second",
            generatedAt: Self.reference.addingTimeInterval(3_600),
            context: Self.context()
        )

        try await sut.setFeedback(.notHelpful, for: first)

        let recent = try await sut.recent(limit: 10)
        XCTAssertNil(recent.first?.feedback, "The newer analysis was not rated")
        XCTAssertEqual(recent.last?.feedback, .notHelpful)
    }

    func testFeedbackCanBeChangedAndCleared() async throws {
        let id = try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())

        try await sut.setFeedback(.helpful, for: id)
        try await sut.setFeedback(.notHelpful, for: id)
        var stored = try await sut.latest()
        XCTAssertEqual(stored?.feedback, .notHelpful)

        try await sut.setFeedback(nil, for: id)
        stored = try await sut.latest()
        XCTAssertNil(stored?.feedback)
    }

    func testDeleteAllRemovesTheWholeHistory() async throws {
        try await sut.save(text: "First", generatedAt: Self.reference, context: Self.context())
        try await sut.save(
            text: "Second",
            generatedAt: Self.reference.addingTimeInterval(3_600),
            context: Self.context()
        )

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
