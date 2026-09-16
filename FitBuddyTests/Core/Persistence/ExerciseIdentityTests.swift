import XCTest
@testable import FitBuddy

/// Unit tests for the identity both entry points into the statistics screen
/// hand over (#162).
///
/// The whole point is that they agree: a movement opened from the exercise
/// list and the same movement opened from a card inside a session have to be
/// the same movement, or the second route answers "not in this window" for an
/// exercise the user is looking at.
final class ExerciseIdentityTests: XCTestCase {
    /// The template id wins wherever the source provides one — that is the key
    /// the cache reads are keyed by.
    func testBothRoutesAgreeWhenTheSourceGivesATemplateID() {
        let fromList = summary(id: "05293BCA", title: "Bench Press (Barbell)").identity
        let fromSession = detail(templateID: "05293BCA", title: "Bench Press (Barbell)").identity

        XCTAssertEqual(fromList.id, fromSession.id)
    }

    /// A rename between sessions must not split the movement: the key is the
    /// template id, not the title.
    func testARenamedExerciseKeepsItsIdentity() {
        let old = detail(templateID: "05293BCA", title: "Bench Press").identity
        let new = detail(templateID: "05293BCA", title: "Bench Press (Barbell)").identity

        XCTAssertEqual(old.id, new.id)
        // The title still follows what the tapped card said, so the screen
        // opens under the name the user just read.
        XCTAssertEqual(new.title, "Bench Press (Barbell)")
    }

    /// Without a template id both sides fall back to the folded title, and
    /// have to fold it the same way.
    func testBothRoutesAgreeOnTheTitleFallback() {
        let fromList = summary(id: ExerciseSummary.key(templateID: nil, title: "Bulgarian Split Squat"),
                               title: "Bulgarian Split Squat").identity
        let fromSession = detail(templateID: nil, title: "Bulgarian Split Squat").identity

        XCTAssertEqual(fromList.id, fromSession.id)
    }

    /// The muscle group comes from the title on both routes, so the header
    /// does not change depending on where the screen was opened from.
    func testTheMuscleGroupMatchesOnBothRoutes() {
        let fromList = summary(id: "x", title: "Bench Press (Barbell)").identity
        let fromSession = detail(templateID: "x", title: "Bench Press (Barbell)").identity

        XCTAssertEqual(fromList.muscleGroup, fromSession.muscleGroup)
        XCTAssertEqual(fromSession.muscleGroup, .chest)
    }

    // MARK: - Helpers

    private func summary(id: String, title: String) -> ExerciseSummary {
        ExerciseSummary(
            id: id,
            title: title,
            muscleGroup: MuscleGroup.from(exerciseTitle: title),
            sessionCount: 3,
            countedSetCount: 9,
            volumeKg: 9_000,
            lastPerformed: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    private func detail(templateID: String?, title: String) -> ExerciseDetail {
        ExerciseDetail(
            index: 0,
            title: title,
            templateID: templateID,
            sets: [SetDetail(index: 0, type: .normal, weightKg: 100, reps: 5,
                             distanceMeters: nil, durationSeconds: nil, rpe: nil)]
        )
    }
}
