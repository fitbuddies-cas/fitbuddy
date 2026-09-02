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
            window: AnalysisWindow(weeks: 8)
        )

        let latest = try await sut.latest()
        let stored = try XCTUnwrap(latest)
        XCTAssertEqual(stored.text, "Add 2.5 kg on bench next session.")
        XCTAssertEqual(stored.generatedAt, Self.reference)
        // The widened window travels with the text (#87) — a restored screen
        // that silently claimed four weeks would misdescribe the advice.
        XCTAssertEqual(stored.window, AnalysisWindow(weeks: 8))
    }

    /// Only the last recommendation is kept — v0 has no history screen, and a
    /// second row would leave `latest()` picking between two.
    func testSavingReplacesThePreviousAnalysis() async throws {
        try await sut.save(text: "First", generatedAt: Self.reference, window: .default)
        try await sut.save(
            text: "Second",
            generatedAt: Self.reference.addingTimeInterval(7 * 3_600),
            window: .default
        )

        let stored = try await sut.latest()
        let context = ModelContext(container)
        XCTAssertEqual(stored?.text, "Second")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AnalysisResult>()), 1)
    }

    func testDeleteAllRemovesTheStoredAnalysis() async throws {
        try await sut.save(text: "First", generatedAt: Self.reference, window: .default)

        try await sut.deleteAll()

        let stored = try await sut.latest()
        XCTAssertNil(stored)
    }

    func testDeleteAllOnAnEmptyStoreSucceeds() async throws {
        try await sut.deleteAll()

        let stored = try await sut.latest()
        XCTAssertNil(stored)
    }
}
