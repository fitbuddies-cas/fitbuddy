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

    /// How many of the movement's sessions in the window Epley could project
    /// an e1RM from — `ExerciseProgression.points.count` over the window.
    ///
    /// Carried here rather than in a second list beside `exercises`: the
    /// evidence already names these movements, and two lists over the same
    /// rows are two chances to disagree (ADR-014, "Was #227 ergänzen muss").
    /// `AnalysisVerdictRule` reads it for stage 2.
    let progressionPoints: Int

    /// `ExerciseProgression.isPlateaued` over the window — ADR-014 stage 3.
    /// Meaningless on its own: only readable where `isPlateauDecidable`.
    let isPlateaued: Bool

    /// Whether `isPlateaued` is an answer rather than a shrug — ADR-014
    /// stage 2, and the same condition `ExerciseProgression.isPlateauDecidable`
    /// applies to the progression this line was built from. Written once, so
    /// the rule and the series cannot come to different conclusions about the
    /// same movement.
    var isPlateauDecidable: Bool {
        progressionPoints > ExerciseProgression.plateauSessionCount
    }

    /// `ExerciseProgression.latestIsWindowBest` over the window — ADR-014
    /// stage 4.
    let latestIsWindowBest: Bool

    init(
        title: String,
        muscleGroup: MuscleGroup,
        workingSet: WorkingSet?,
        smallestStepKg: Double? = nil,
        twoForTwo: TwoForTwoCondition = .notCheckable,
        progressionPoints: Int = 0,
        isPlateaued: Bool = false,
        latestIsWindowBest: Bool = false
    ) {
        self.title = title
        self.muscleGroup = muscleGroup
        self.workingSet = workingSet
        self.smallestStepKg = smallestStepKg
        self.twoForTwo = twoForTwo
        self.progressionPoints = progressionPoints
        self.isPlateaued = isPlateaued
        self.latestIsWindowBest = latestIsWindowBest
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
            twoForTwo: TwoForTwoCondition.evaluate(sessions: listing.inWindow.sessions),
            // The same three facts `plateauVerdict(_:)` prints into the
            // prompt line and then throws away — ADR-014 stages 2 to 4 read
            // them here instead of recomputing them.
            progressionPoints: listing.inWindow.points.count,
            isPlateaued: listing.inWindow.isPlateaued,
            latestIsWindowBest: listing.inWindow.latestIsWindowBest
        )
    }
}
