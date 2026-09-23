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
    /// Whether the exercise has earned a load increase (ADR-013, #232) — what
    /// the line says after the rep target, and what a progression card is
    /// checked against (#233). The load range itself is derived from the
    /// fields above by `ProgressionBand.range(for:)`.
    let twoForTwo: TwoForTwoCondition

    init(
        title: String,
        muscleGroup: MuscleGroup,
        workingSet: WorkingSet?,
        smallestStepKg: Double? = nil,
        twoForTwo: TwoForTwoCondition = .notCheckable
    ) {
        self.title = title
        self.muscleGroup = muscleGroup
        self.workingSet = workingSet
        self.smallestStepKg = smallestStepKg
        self.twoForTwo = twoForTwo
    }

    /// The listed exercise a prompt line describes, from the same listing
    /// the line is rendered from (#232).
    ///
    /// The one place the working set, the step and the 2-for-2 verdict are
    /// derived: `AnalysisPromptBuilder.listedExercises` builds the evidence
    /// through it and `StrengthPromptSection` the line, so the range the
    /// model is shown and the range a card is checked against (#233) cannot
    /// drift apart.
    static func make(
        title: String,
        muscleGroup: MuscleGroup,
        listing: (inWindow: ExerciseProgression, last: ExerciseHistoryEntry)
    ) -> ListedExercise {
        let working = listing.last.heaviestWorkingSet
        return ListedExercise(
            title: title,
            muscleGroup: muscleGroup,
            workingSet: working,
            smallestStepKg: working.flatMap {
                AnalysisPromptBuilder.smallestStep(in: listing.inWindow.sessions, latest: $0)
            },
            twoForTwo: TwoForTwoCondition.evaluate(sessions: listing.inWindow.sessions)
        )
    }
}
