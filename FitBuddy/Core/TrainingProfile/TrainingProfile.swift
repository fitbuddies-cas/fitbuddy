import Foundation

/// What the user told us about their training (US-13).
///
/// Both fields are optional and independent: a user may answer one question
/// and leave the other, and half an answer is still worth more to the
/// recommendation than none. `nil` for both is a profile that says nothing —
/// `isEmpty` — and the prompt leaves the section out entirely rather than
/// printing a heading with nothing under it (#192).
struct TrainingProfile: Equatable, Sendable {
    var goal: TrainingGoal?
    var experience: TrainingExperience?

    init(goal: TrainingGoal? = nil, experience: TrainingExperience? = nil) {
        self.goal = goal
        self.experience = experience
    }

    /// Nothing was answered — indistinguishable from never having been asked,
    /// and treated the same way everywhere.
    var isEmpty: Bool { goal == nil && experience == nil }
}
