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
/// `-fbSeedAnalysis recover` (or `progress`, `hold`, `thin`, `endurance`,
/// `overall`) picks the report (#179, #170, #186).
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
        // Design 3.4c/3.4d: the generic cards of #186 — an endurance report
        // whose figures are all in endurance units (US-15 AC5), and an
        // overall-load one led by the interference card.
        "endurance": AnalysisReportSamples.endurance,
        "overall": AnalysisReportSamples.overallLoad,
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

    /// The context line a seeded report rests on where there is no cache
    /// behind it: its own session count, over the default window, all Hevy.
    static func context(forReportNamed name: String) -> AnalysisContext {
        AnalysisContext(sessionCount: sessionCounts[name] ?? defaultSessionCount, window: .default)
    }

    /// The context line a seeded report rests on when a workout profile was
    /// seeded with it (#188): the window that profile's cache actually holds,
    /// counted per source and per domain.
    ///
    /// Read from the cache rather than fixed, so a UI test over the `mixed`
    /// profile asserts the cross-source line of US-15 AC4 — "12 Hevy · 12
    /// Strava sessions" — as the app computes it, not as a fixture spells it.
    /// The counting, the window ladder and the preselected profile are the
    /// view model's own (`AnalysisViewModel.sessionCounts(in:from:)`,
    /// `AnalysisProfileOptions`), so the seeded line and a real run's cannot
    /// drift apart.
    ///
    /// Falls back to the fixed line for a cache the ladder finds nothing in —
    /// a report seeded without a profile behind it still has a basis to name.
    static func context(
        forReportNamed name: String,
        summaries: [WorkoutSummary],
        now: Date,
        calendar: Calendar = .current
    ) -> AnalysisContext {
        guard let window = AnalysisWindow.resolve(for: summaries, endingAt: now, calendar: calendar)
        else { return context(forReportNamed: name) }
        let start = window.start(endingAt: now, calendar: calendar)
        let counts = AnalysisViewModel.sessionCounts(in: summaries, from: start)
        let profile = AnalysisProfileOptions(domainCounts: counts.domains).preselected
        return AnalysisContext(
            sessionCounts: counts.sources,
            domainCounts: counts.domains,
            analysedCounts: counts.domains.filter { profile.covers($0.key) },
            window: window,
            analysisProfile: profile
        )
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
        let reference = now()
        do {
            try await store.deleteAll()
            try await store.save(
                text: report.summary,
                report: report,
                provider: .claude,
                generatedAt: reference,
                context: await context(
                    forReportNamed: name,
                    container: container,
                    launchArguments: launchArguments,
                    now: reference
                ),
                // No confirmation: nothing was sent for a seeded row, and a
                // made-up one would be shown as evidence in the history
                // detail (#268).
                confirmation: nil
            )
            logger.debug("Seeded a stored analysis")
        } catch {
            logger.error("Seeding the analysis failed: \(error, privacy: .public)")
        }
    }

    /// The basis to store the report with: the seeded cache's own window where
    /// a workout profile was seeded too, and the fixed line otherwise.
    ///
    /// `MockDataSeeder` runs first (`RootView`), so by the time this reads the
    /// cache the profile is already in it. A read that fails leaves the fixed
    /// line — the seeded report is still worth showing, and the test that
    /// needed the breakdown fails on its own assertion.
    private static func context(
        forReportNamed name: String,
        container: ModelContainer,
        launchArguments: [String],
        now: Date
    ) async -> AnalysisContext {
        guard MockDataSeeder.requestedProfile(in: launchArguments) != nil else {
            return context(forReportNamed: name)
        }
        do {
            let summaries = try await WorkoutStore(modelContainer: container).workoutSummaries(
                since: AnalysisWindow.widest.previousStart(endingAt: now)
            )
            return context(forReportNamed: name, summaries: summaries, now: now)
        } catch {
            logger.error("Seeded basis not read: \(error, privacy: .public)")
            return context(forReportNamed: name)
        }
    }
}

#endif
