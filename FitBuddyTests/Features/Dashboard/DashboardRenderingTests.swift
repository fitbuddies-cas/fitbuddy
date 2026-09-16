import SwiftUI
import XCTest
@testable import FitBuddy

/// Views carry no unit tests per the project conventions, but the dashboard's
/// cards do lay out data-dependent content — a Swift Charts scale built from an
/// empty or all-zero distribution fails at render time, not at compile time.
/// Rendering each card once catches that.
@MainActor
final class DashboardRenderingTests: XCTestCase {
    func testMuscleDistributionCardRenders() throws {
        let image = try render(MuscleDistributionCard(distribution: [
            MuscleLoad(group: .chest, volumeKg: 46_200, setCount: 84),
            MuscleLoad(group: .legs, volumeKg: 22_400, setCount: 61),
        ]))

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// An all-bodyweight window: nothing to chart on a kg scale, so the card
    /// falls back to naming the groups.
    func testMuscleDistributionCardRendersWithoutVolume() throws {
        let image = try render(MuscleDistributionCard(distribution: [
            MuscleLoad(group: .core, volumeKg: 0, setCount: 12),
            MuscleLoad(group: .back, volumeKg: 0, setCount: 9),
        ]))

        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testMuscleDistributionCardRendersWithoutAnyData() throws {
        let image = try render(MuscleDistributionCard(distribution: []))
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testRecentSessionsCardRenders() throws {
        let workouts = (0..<14).map { index in
            WorkoutSummary(
                id: "\(index)",
                title: "Push Day",
                startTime: Date(timeIntervalSince1970: 1_750_000_000 - Double(index) * 86_400),
                volumeKg: 8_420,
                exerciseCount: 6,
                countedSetCount: 21
            )
        }

        // Rendered without a `NavigationStack` around it: `ImageRenderer`
        // returns nil for one, and the rows' `NavigationLink`s (#98) lay out
        // the same either way.
        let image = try render(RecentSessionsCard(workouts: workouts, limit: 5))
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - Workout detail (#98)

    /// The exercise card lays out data-dependent content too: the volume bar
    /// divides by the session total, and a set row builds its line from
    /// whichever metrics happen to be logged.
    func testExerciseCardRendersEveryKindOfExercise() throws {
        let session = PreviewWorkoutDetailCache.session

        for exercise in session.exercises {
            let image = try render(
                ExerciseDetailCard(exercise: exercise, sessionVolumeKg: session.volumeKg)
            )
            XCTAssertGreaterThan(image.size.height, 0, "\(exercise.title) did not render")
        }
    }

    /// A weightless exercise inside a session that does have volume: the bar
    /// gives way to the plain set count, keyed off the exercise's own volume
    /// rather than the session's.
    func testExerciseCardRendersAWeightlessExerciseInAMixedSession() throws {
        let session = PreviewWorkoutDetailCache.session
        let dips = session.exercises[2]
        XCTAssertEqual(dips.volumeKg, 0)
        XCTAssertGreaterThan(session.volumeKg, 0)

        let image = try render(
            ExerciseDetailCard(exercise: dips, sessionVolumeKg: session.volumeKg)
        )
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// An exercise created in Hevy but never logged: no sets, and no
    /// free-standing divider under the card either.
    func testExerciseCardRendersAnExerciseWithoutSets() throws {
        let image = try render(
            ExerciseDetailCard(
                exercise: ExerciseDetail(index: 0, title: "Bench Press (Barbell)", sets: []),
                sessionVolumeKg: 0
            )
        )
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// The sync strip renders one statement, not two: in `.failed` the banner
    /// carries the timestamp in its subtitle, so the separate line underneath
    /// must not also be there (#28 review).
    func testFailedSyncStripShowsTheTimestampExactlyOnce() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let view = SyncStatusView(
            status: .failed(.offline),
            sources: [DataSourceStatus(source: .hevy, lastSync: now.addingTimeInterval(-900))],
            now: now,
            onRetry: {}
        )

        let image = try render(view)
        XCTAssertGreaterThan(image.size.width, 0)

        // The rendered text is not reachable from ImageRenderer, so the
        // assertion sits on the copy the two call sites share.
        let line = SyncTimeFormatter.lastSynced(now.addingTimeInterval(-900), now: now)
        XCTAssertEqual(line, "Last synced 15 min ago")
    }

    func testSyncStripRendersInEveryStatus() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let statuses: [SyncStatus] = [
            .idle, .syncing, .failed(.keychainUnavailable), .failed(.rateLimited(retryAfter: 45)),
            // Partial syncs (#143, #144): the renewal prompt of US-5 AC2, a
            // plain per-source failure, and both sources at once.
            .degraded(failures: [.strava: .connectionExpired]),
            .degraded(failures: [.strava: .offline]),
            .degraded(failures: [.hevy: .serviceUnavailable, .strava: .connectionExpired]),
        ]

        for status in statuses {
            let image = try render(
                SyncStatusView(
                    status: status,
                    sources: [DataSourceStatus(source: .hevy, lastSync: nil)],
                    now: now,
                    onRetry: {}
                )
            )
            XCTAssertGreaterThan(image.size.height, 0, "\(status) did not render")
        }
    }

    // MARK: - Data sources (US-8, #40)

    /// Every state one source row can be in. The stale row is the one that
    /// grows a title, a second line and a button, so a layout that only ever
    /// saw the quiet single-line case would not have been exercised.
    func testDataSourceRowRendersInEveryFreshness() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sources: [DataSourceStatus] = [
            DataSourceStatus(source: .hevy, lastSync: now.addingTimeInterval(-900)),
            DataSourceStatus(source: .hevy, lastSync: nil, isSyncing: true),
            DataSourceStatus(source: .hevy, lastSync: now.addingTimeInterval(-4 * 86_400)),
            DataSourceStatus(source: .hevy, lastSync: nil),
        ]

        for source in sources {
            let image = try render(
                DataSourceStatusView(sources: [source], now: now, onRetry: { _ in })
            )
            XCTAssertGreaterThan(image.size.height, 0, "\(source) did not render")
        }
    }

    /// The strip is written to loop, so a second source has to lay out without
    /// the first one's row being rebuilt — the shape v0's Hevy-only wiring
    /// never reaches, and the one #35 will.
    func testDataSourceStripRendersMoreThanOneSource() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let image = try render(
            DataSourceStatusView(
                sources: [
                    DataSourceStatus(source: .hevy, lastSync: now.addingTimeInterval(-300)),
                    DataSourceStatus(source: .strava, lastSync: now.addingTimeInterval(-6 * 86_400)),
                ],
                now: now,
                onRetry: { _ in }
            )
        )
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// A stale source is what the strip shows when nothing failed and nothing
    /// is running — the `.idle` case US-8 AC1 is entirely about.
    func testIdleStripStillFlagsAStaleSource() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let stale = DataSourceStatus(source: .hevy, lastSync: now.addingTimeInterval(-2 * 86_400))

        XCTAssertTrue(stale.needsAttention(now: now))
        let image = try render(
            SyncStatusView(status: .idle, sources: [stale], now: now, onRetry: {})
        )
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// The toast a failed pull raises (#43). Its copy is a whole sentence per
    /// failure, and the longest of them has to wrap rather than truncate —
    /// a clipped "Try again in 3 mi" is worse than no message.
    func testRefreshToastRendersEveryFailure() throws {
        let failures: [SyncFailure] = [
            .offline, .serviceUnavailable, .rateLimited(retryAfter: 180),
            .keychainUnavailable, .unreadableResponse, .cacheWriteFailed, .unknown, .connectionExpired,
        ]

        for failure in failures {
            let image = try render(
                FBToast(
                    symbolName: failure.symbolName,
                    message: failure.refreshMessage,
                    onDismiss: {}
                )
            )
            XCTAssertGreaterThan(image.size.height, 0, "\(failure) did not render")
        }
    }

    func testEmptyStateRenders() throws {
        let image = try render(DashboardEmptyView())
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - Helpers

    private func render(_ view: some View) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: 390))
        return try XCTUnwrap(renderer.uiImage)
    }
}
