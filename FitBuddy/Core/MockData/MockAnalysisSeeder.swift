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
/// `-fbSeedAnalysis` turns it on; without the argument nothing here runs.
enum MockAnalysisSeeder {
    static let launchArgument = "-fbSeedAnalysis"

    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "MockAnalysisSeeder")

    static func isRequested(in launchArguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        launchArguments.contains(launchArgument)
    }

    /// Replaces the stored history with the progress report of design 3.4.
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
        let store = AnalysisResultStore(modelContainer: container)
        let report = AnalysisReportSamples.progress
        do {
            try await store.deleteAll()
            try await store.save(
                text: report.summary,
                report: report,
                provider: .claude,
                generatedAt: now(),
                context: AnalysisContext(sessionCount: 14, window: .default)
            )
            logger.debug("Seeded a stored analysis")
        } catch {
            logger.error("Seeding the analysis failed: \(error, privacy: .public)")
        }
    }
}

#endif
