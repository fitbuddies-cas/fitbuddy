import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisHistoryViewModel` (US-3 AC11, #117): loading the
/// stored analyses, deleting one, and the empty state behind both.
@MainActor
final class AnalysisHistoryViewModelTests: XCTestCase {
    private static let reference = Date(timeIntervalSince1970: 1_788_000_000)

    private func entry(
        _ text: String,
        hoursAgo: Double,
        feedback: AnalysisFeedback? = nil
    ) -> AnalysisResultSnapshot {
        AnalysisResultSnapshot(
            id: UUID(),
            text: text,
            generatedAt: Self.reference.addingTimeInterval(-hoursAgo * 3_600),
            context: AnalysisContext(sessionCount: 12, window: .default),
            feedback: feedback
        )
    }

    func testLoadPublishesTheStoredAnalysesNewestFirst() async {
        let store = StubAnalysisResultStore(entries: [
            entry("Newest", hoursAgo: 1),
            entry("Middle", hoursAgo: 24),
            entry("Oldest", hoursAgo: 72)
        ])
        let sut = AnalysisHistoryViewModel(store: store)

        await sut.load()

        XCTAssertEqual(sut.entries.map(\.text), ["Newest", "Middle", "Oldest"])
        XCTAssertTrue(sut.isLoaded)
        XCTAssertNil(sut.failure)
    }

    func testLoadOnAnEmptyStoreLeavesAnEmptyList() async {
        let sut = AnalysisHistoryViewModel(store: StubAnalysisResultStore())

        await sut.load()

        XCTAssertTrue(sut.entries.isEmpty)
        XCTAssertTrue(sut.isLoaded)
    }

    /// Before the first read there is nothing to show and nothing to say —
    /// the screen must not claim an empty history it has not looked at.
    func testNothingIsLoadedBeforeTheFirstRead() {
        let sut = AnalysisHistoryViewModel(store: StubAnalysisResultStore())

        XCTAssertTrue(sut.entries.isEmpty)
        XCTAssertFalse(sut.isLoaded)
    }

    func testLoadReadsAtMostTheStoresOwnLimit() async {
        let store = StubAnalysisResultStore(entries: (0..<25).map { index in
            entry("Analysis \(index)", hoursAgo: Double(index))
        })
        let sut = AnalysisHistoryViewModel(store: store)

        await sut.load()

        XCTAssertEqual(sut.entries.count, AnalysisResultStore.historyLimit)
    }

    func testAFailedReadIsReportedAndLeavesTheListEmpty() async {
        let store = StubAnalysisResultStore(entries: [entry("Newest", hoursAgo: 1)])
        await store.setReadFails(true)
        let sut = AnalysisHistoryViewModel(store: store)

        await sut.load()

        XCTAssertTrue(sut.entries.isEmpty)
        XCTAssertTrue(sut.isLoaded)
        XCTAssertNotNil(sut.failure)
    }

    // MARK: - Delete (US-3 AC11)

    func testDeleteRemovesOnlyThatAnalysis() async {
        let doomed = entry("Doomed", hoursAgo: 1)
        let store = StubAnalysisResultStore(entries: [doomed, entry("Kept", hoursAgo: 24)])
        let sut = AnalysisHistoryViewModel(store: store)
        await sut.load()

        await sut.delete(id: doomed.id)

        XCTAssertEqual(sut.entries.map(\.text), ["Kept"])
        let stored = await store.entries
        XCTAssertEqual(stored.map(\.text), ["Kept"])
        XCTAssertNil(sut.failure)
    }

    func testDeletingTheLastAnalysisLeavesAnEmptyList() async {
        let only = entry("Only", hoursAgo: 1)
        let sut = AnalysisHistoryViewModel(store: StubAnalysisResultStore(entries: [only]))
        await sut.load()

        await sut.delete(id: only.id)

        XCTAssertTrue(sut.entries.isEmpty)
    }

    /// A row that vanishes from the screen but not from the device is the one
    /// outcome a deletion must never have.
    func testAFailedDeletePutsTheRowBackAndSaysSo() async {
        let doomed = entry("Doomed", hoursAgo: 1)
        let store = StubAnalysisResultStore(entries: [doomed, entry("Kept", hoursAgo: 24)])
        await store.setDeleteFails(true)
        let sut = AnalysisHistoryViewModel(store: store)
        await sut.load()

        await sut.delete(id: doomed.id)

        XCTAssertEqual(sut.entries.map(\.text), ["Doomed", "Kept"])
        XCTAssertNotNil(sut.failure)
    }

    func testDeletingAnUnknownIdChangesNothing() async {
        let store = StubAnalysisResultStore(entries: [entry("Kept", hoursAgo: 1)])
        let sut = AnalysisHistoryViewModel(store: store)
        await sut.load()

        await sut.delete(id: UUID())

        XCTAssertEqual(sut.entries.map(\.text), ["Kept"])
        XCTAssertNil(sut.failure)
    }

    /// The verdict travels with the row, so the list can show what was said
    /// about each analysis without matching anything up by timestamp.
    func testTheStoredVerdictTravelsWithTheEntry() async {
        let store = StubAnalysisResultStore(entries: [
            entry("Rated", hoursAgo: 1, feedback: .notHelpful),
            entry("Unrated", hoursAgo: 24)
        ])
        let sut = AnalysisHistoryViewModel(store: store)

        await sut.load()

        XCTAssertEqual(sut.entries.first?.feedback, .notHelpful)
        XCTAssertNil(sut.entries.last?.feedback)
    }
}
