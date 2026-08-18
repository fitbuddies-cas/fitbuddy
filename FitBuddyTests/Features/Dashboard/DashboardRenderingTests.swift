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

    /// An all-bodyweight window: every bar is zero, so the chart's x scale has
    /// to stay valid without any volume to scale to.
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
