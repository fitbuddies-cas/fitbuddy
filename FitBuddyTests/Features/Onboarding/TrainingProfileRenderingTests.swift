import SwiftUI
import XCTest
@testable import FitBuddy

/// Rendering smoke tests for the profile option row (US-13, #190).
///
/// Views carry no unit tests in this project; the row is the narrow exception
/// the dashboard and the progression chart make too — it is the one piece of
/// this screen with two visual states, and a `ScrollView`'s contents cannot be
/// rendered at all outside the simulator.
@MainActor
final class TrainingProfileRenderingTests: XCTestCase {
    func testEveryGoalRenders() throws {
        for goal in TrainingGoal.allCases {
            let image = try render(
                TrainingProfileOptionRow(title: goal.displayName, isSelected: false) {}
            )
            XCTAssertGreaterThan(image.size.height, 0, "\(goal) did not render")
        }
    }

    func testEveryExperienceRenders() throws {
        for experience in TrainingExperience.allCases {
            let image = try render(
                TrainingProfileOptionRow(title: experience.displayName, isSelected: true) {}
            )
            XCTAssertGreaterThan(image.size.height, 0, "\(experience) did not render")
        }
    }

    /// Selected and unselected must not differ in height, or picking an answer
    /// would make the list jump under the user's finger.
    func testSelectionDoesNotChangeTheRowHeight() throws {
        let unselected = try render(
            TrainingProfileOptionRow(title: "Improve endurance", isSelected: false) {}
        )
        let selected = try render(
            TrainingProfileOptionRow(title: "Improve endurance", isSelected: true) {}
        )

        XCTAssertEqual(unselected.size.height, selected.size.height, accuracy: 0.5)
    }

    private func render(_ view: some View) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: 362))
        return try XCTUnwrap(renderer.uiImage)
    }
}
