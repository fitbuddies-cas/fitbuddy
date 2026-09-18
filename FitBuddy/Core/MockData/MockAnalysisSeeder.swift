import Foundation
import OSLog
import SwiftData

// Test support: excluded from Release builds like `MockDataSeeder`, so no
// fabricated recommendation can reach a TestFlight binary.
#if DEBUG

/// Stores one analysis with a validated report before the first screen reads
/// the history, so a UI test lands on the result cards without a provider key
/// or a network call (#177).
///
/// The counterpart to `MockDataSeeder` for the analysis tab: that one fills
/// the workout cache, this one the result store the tab restores from (US-3
/// AC10). The report goes through the real `AnalysisResultStore`, so the test
/// also covers its persistence and the restore path.
///
/// `-fbSeedAnalysis` turns it on and stores the progress report of design 3.4;
/// `-fbSeedAnalysis recover` (or `progress`, `hold`, `thin`) picks the report
/// (#179, #170).
/// Without the argument nothing here runs.
enum MockAnalysisSeeder {
    static let launchArgument = "-fbSeedAnalysis"

    /// The report a bare `-fbSeedAnalysis` stores.
    static let defaultReportName = "progress"

    /// The reports a launch can ask for, by the name after the argument.
    static let reports: [String: ValidatedAnalysisReport] = [
        "progress": AnalysisReportSamples.progress,
        "recover": AnalysisReportSamples.recover,
        "hold": AnalysisReportSamples.hold,
        // Design 3.4b: no cards, the full analysis open (#170).
        "thin": AnalysisReportSamples.thin,
    ]

    /// Sessions the context line of a seeded report names. 14 as in design
    /// 3.4/3.5; the thin report rests on 2, as design 3.4b draws it.
    static let defaultSessionCount = 14
    static let sessionCounts: [String: Int] = ["thin": 2]

    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "MockAnalysisSeeder")

    static func isRequested(in launchArguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        launchArguments.contains(launchArgument)
    }

    /// The report the launch asked for, or `nil` when it asked for none.
    ///
    /// A bare argument — last, or followed by another flag — means the
    /// progress report, as before #179. An unknown name means none, as an
    /// unknown profile does in `MockDataSeeder`: a typo leaves the tab empty
    /// rather than on a silently different report.
    static func requestedReport(
        in launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) -> ValidatedAnalysisReport? {
        requestedReportName(in: launchArguments).flatMap { reports[$0] }
    }

    /// The context line a seeded report rests on: its own session count, over
    /// the default window.
    static func context(forReportNamed name: String) -> AnalysisContext {
        AnalysisContext(sessionCount: sessionCounts[name] ?? defaultSessionCount, window: .default)
    }

    /// The report name the launch asked for — the default for a bare argument
    /// — or `nil` without the argument.
    private static func requestedReportName(in launchArguments: [String]) -> String? {
        guard let flag = launchArguments.firstIndex(of: launchArgument) else { return nil }
        let value = launchArguments.index(after: flag)
        guard value < launchArguments.endIndex, !launchArguments[value].hasPrefix("-") else {
            return defaultReportName
        }
        return launchArguments[value]
    }

    /// Replaces the stored history with the requested report.
    ///
    /// Replaces rather than appends: `-fbResetState` clears the Keychain and
    /// the defaults but not SwiftData, so without the wipe a second launch
    /// would find two rows and a history link the test did not ask for.
    ///
    /// Failures are logged and swallowed, as in `MockDataSeeder`: the test
    /// that needed the row fails on its next assertion either way.
    static func seedIfRequested(
        container: ModelContainer,
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        now: () -> Date = Date.init
    ) async {
        guard isRequested(in: launchArguments) else { return }
        guard let name = requestedReportName(in: launchArguments), let report = reports[name] else {
            logger.error("Unknown analysis report requested; nothing seeded")
            return
        }
        let store = AnalysisResultStore(modelContainer: container)
        do {
            try await store.deleteAll()
            try await store.save(
                text: report.summary,
                report: report,
                provider: .claude,
                generatedAt: now(),
                context: context(forReportNamed: name)
            )
            logger.debug("Seeded a stored analysis")
        } catch {
            logger.error("Seeding the analysis failed: \(error, privacy: .public)")
        }
    }
}

#endif
