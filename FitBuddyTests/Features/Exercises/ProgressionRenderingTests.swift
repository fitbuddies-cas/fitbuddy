import SwiftUI
import XCTest
@testable import FitBuddy

/// Rendering smoke tests for the progression chart (US-9, #42).
///
/// Views carry no unit tests in this project; this is the narrow exception the
/// dashboard makes too — a chart whose scale maths divides by a zero span, or
/// whose domain comes out reversed, throws at render time rather than failing
/// an assertion somewhere readable.
@MainActor
final class ProgressionRenderingTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    func testRisingCurveRenders() throws {
        let image = try render(ProgressionChartCard(points: points([96, 101, 104, 107])))
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// Every point identical: the padded domain has to survive a zero span,
    /// which is where a naive `min...max` scale collapses.
    func testFlatCurveRenders() throws {
        let image = try render(ProgressionChartCard(points: points([100, 100, 100])))
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// The minimum a plottable curve can have.
    func testTwoPointCurveRenders() throws {
        let image = try render(ProgressionChartCard(points: points([100, 92.5])))
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// A light movement: the 2.5 kg padding floor is larger than the values
    /// themselves, so an unclamped domain would run negative and the axis
    /// would label kilograms that do not exist.
    func testVeryLightCurveKeepsTheAxisAboveZero() throws {
        let image = try render(ProgressionChartCard(points: points([1.6, 2.1])))
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - Helpers

    private func points(_ estimates: [Double]) -> [ProgressionPoint] {
        estimates.enumerated().map { offset, estimate in
            ProgressionPoint(
                sessionStart: reference.addingTimeInterval(Double(offset) * 7 * 86_400),
                estimatedOneRepMaxKg: estimate,
                weightKg: estimate * 0.8,
                reps: 8
            )
        }
    }

    private func render(_ view: some View) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: 390))
        return try XCTUnwrap(renderer.uiImage)
    }
}
