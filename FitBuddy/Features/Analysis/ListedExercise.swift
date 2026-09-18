import Foundation

/// One line of the prompt's Exercises section, reduced to what a progression
/// card is checked against (#175).
///
/// Built by `AnalysisPromptBuilder.listedExercises(...)` from the same data and
/// the same session choice as the line itself, so the validator compares a
/// card with the figure the model was actually shown.
struct ListedExercise: Equatable, Sendable {
    /// The title exactly as the prompt spells it.
    let title: String
    let muscleGroup: MuscleGroup
    /// The heaviest working set of the most recent session the line describes
    /// — `nil` when that session carried no set with both weight and reps, so
    /// there is no weight a load change could start from.
    let workingSet: WorkingSet?
    /// The "Smallest logged step" the line names, from
    /// `AnalysisPromptBuilder.smallestStep(in:latest:)` — `nil` when the line
    /// names none. Rule 6 then allows no load increase for a non-barbell
    /// exercise (reps instead); a barbell exercise always gets 2.5 kg,
    /// whatever is listed here.
    let smallestStepKg: Double?

    init(title: String, muscleGroup: MuscleGroup, workingSet: WorkingSet?, smallestStepKg: Double? = nil) {
        self.title = title
        self.muscleGroup = muscleGroup
        self.workingSet = workingSet
        self.smallestStepKg = smallestStepKg
    }
}
