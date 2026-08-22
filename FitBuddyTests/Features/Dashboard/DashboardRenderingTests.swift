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

        let image = try render(RecentSessionsCard(workouts: workouts, limit: 5))
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// The sync strip renders one statement, not two: in `.failed` the banner
    /// carries the timestamp in its subtitle, so the separate line underneath
    /// must not also be there (#28 review).
    func testFailedSyncStripShowsTheTimestampExactlyOnce() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let view = SyncStatusView(
            status: .failed(.offline),
            lastSync: now.addingTimeInterval(-900),
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
        ]

        for status in statuses {
            let image = try render(
                SyncStatusView(status: status, lastSync: nil, now: now, onRetry: {})
            )
            XCTAssertGreaterThan(image.size.height, 0, "\(status) did not render")
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
