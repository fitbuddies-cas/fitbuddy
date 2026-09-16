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

    // MARK: - Report and provider (US-14 AC6, #176)

    /// The history detail has to show exactly the cards the user saw, and
    /// the badge the provider that wrote them.
    func testSavedReportRoundTripsWithItsVersionAndProvider() async throws {
        let report = ValidatedAnalysisReportFixtures.everyCard
        try await sut.save(
            text: report.summary,
            report: report,
            provider: .gemini,
            generatedAt: Self.reference,
            context: Self.context()
        )

        let latest = try await sut.latest()
        let stored = try XCTUnwrap(latest)
        XCTAssertEqual(stored.report, report)
        XCTAssertEqual(stored.provider, .gemini)
        XCTAssertEqual(stored.text, report.summary)

        let row = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<AnalysisResult>()).first)
        XCTAssertEqual(row.reportVersion, AnalysisReportFormat.validatedReportV1)
        XCTAssertNotNil(row.reportJSON)
        XCTAssertEqual(row.providerRawValue, "gemini")
    }

    func testProseIsStoredWithoutAReport() async throws {
        try await sut.save(
            text: "Add 2.5 kg on bench next session.",
            report: nil,
            provider: .claude,
            generatedAt: Self.reference,
            context: Self.context()
        )

        let latest = try await sut.latest()
        let stored = try XCTUnwrap(latest)
        XCTAssertNil(stored.report)
        XCTAssertEqual(stored.provider, .claude)

        let row = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<AnalysisResult>()).first)
        XCTAssertEqual(row.reportVersion, AnalysisReportFormat.prose)
        XCTAssertNil(row.reportJSON)
    }

    /// A report that does not decode must neither crash the read nor drop
    /// the row: the text is stored alongside for exactly this case.
    func testCorruptReportJSONFallsBackToTheText() async throws {
        try insertRow(
            text: "Prose fallback.",
            reportJSON: Data("{\"headline\": \"Cut off".utf8),
            reportVersion: AnalysisReportFormat.validatedReportV1
        )

        let recent = try await sut.recent(limit: 10)

        XCTAssertEqual(recent.map(\.text), ["Prose fallback."])
        XCTAssertNil(recent.first?.report)
    }

    /// A newer build may store a format this one does not know. Even valid
    /// JSON of today's shape is not read under a version it does not claim.
    func testUnknownReportVersionFallsBackToTheText() async throws {
        let json = try JSONEncoder().encode(ValidatedAnalysisReportFixtures.everyCard)
        try insertRow(text: "Prose fallback.", reportJSON: json, reportVersion: 99)

        let recent = try await sut.recent(limit: 10)

        XCTAssertEqual(recent.map(\.text), ["Prose fallback."])
        XCTAssertNil(recent.first?.report)
    }

    /// A version 1 row written before the report had a lead (#170) still
    /// reads as a report: the lead is derived from its summary.
    func testReportStoredWithoutALeadDerivesItFromTheSummary() async throws {
        let json = Data("""
        {"headline": "Hold steady.", "verdict": "hold", "cards": [],
         "summary": "Two sessions are too few to judge a trend. Keep the weights. Log another week."}
        """.utf8)
        try insertRow(text: "Prose fallback.", reportJSON: json, reportVersion: AnalysisReportFormat.validatedReportV1)

        let latest = try await sut.latest()

        XCTAssertEqual(latest?.report, ValidatedAnalysisReport(
            headline: "Hold steady.",
            verdict: .hold,
            lead: "Two sessions are too few to judge a trend. Keep the weights.",
            cards: [],
            summary: "Two sessions are too few to judge a trend. Keep the weights. Log another week."
        ))
    }

    /// A stored blank lead is derived the same way.
    func testReportStoredWithABlankLeadDerivesItFromTheSummary() throws {
        let json = Data(#"{"headline": "Go.", "verdict": "progress", "lead": " ", "cards": [], "summary": "Add 2.5 kg."}"#.utf8)

        let report = AnalysisReportFormat.decode(json, version: AnalysisReportFormat.validatedReportV1)

        XCTAssertEqual(report?.lead, "Add 2.5 kg.")
    }

    /// A version without bytes is as unreadable as bytes without a version.
    func testReportVersionWithoutJSONFallsBackToTheText() async throws {
        try insertRow(text: "Prose fallback.", reportJSON: nil, reportVersion: AnalysisReportFormat.validatedReportV1)

        let latest = try await sut.latest()

        XCTAssertEqual(latest?.text, "Prose fallback.")
        XCTAssertNil(latest?.report)
    }

    func testUnknownProviderReadsAsNoProvider() async throws {
        try insertRow(text: "From a newer build.", providerRawValue: "openai")

        let latest = try await sut.latest()

        XCTAssertEqual(latest?.text, "From a newer build.")
        XCTAssertNil(latest?.provider)
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
    ///
    /// Every other row carries a report (#176): the stored cards change what
    /// a row holds, not how many rows are kept.
    func testTheStoreNeverHoldsMoreThanTwentyAnalyses() async throws {
        for index in 0..<(AnalysisHistoryLimit.rows + 5) {
            try await sut.save(
                text: "Analysis \(index)",
                report: index.isMultiple(of: 2) ? ValidatedAnalysisReportFixtures.everyCard : nil,
                provider: .claude,
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
        XCTAssertEqual(recent.first?.report, ValidatedAnalysisReportFixtures.everyCard)
        XCTAssertEqual(recent.last?.text, "Analysis 5")
        XCTAssertNil(recent.last?.report)
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
    /// analysis screen and a second for the settings screen, `WorkoutSyncService` a
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

    /// Writes a row directly, bypassing `save`, to store what `save` itself
    /// never writes — bytes that do not decode, a format or provider from a
    /// newer build.
    private func insertRow(
        text: String,
        reportJSON: Data? = nil,
        reportVersion: Int = AnalysisReportFormat.prose,
        providerRawValue: String? = nil
    ) throws {
        let context = ModelContext(container)
        context.insert(
            AnalysisResult(
                text: text,
                generatedAt: Self.reference,
                windowWeeks: 4,
                sessionCount: 12,
                reportJSON: reportJSON,
                reportVersion: reportVersion,
                providerRawValue: providerRawValue
            )
        )
        try context.save()
    }

    private static func context(sessions: Int = 12, weeks: Int = 4) -> AnalysisContext {
        AnalysisContext(sessionCount: sessions, window: AnalysisWindow(weeks: weeks))
    }
}
