import Foundation

/// The little a screen needs to open one movement's statistics: which movement
/// it is, and what to call it before the read lands (#162).
///
/// Two screens push the progression curve — a row in the exercise list and a
/// card in a workout's detail — and they hold very different objects. Handing
/// the view model an `ExerciseSummary` worked while the list was the only way
/// in; from a session there is no summary, and assembling a half-filled one
/// just to satisfy the initialiser would put invented totals into a type whose
/// whole point is that its totals are real.
///
/// `Hashable` because it travels as a `NavigationLink` value.
struct ExerciseIdentity: Hashable, Sendable {
    /// `ExerciseSummary.key(templateID:title:)` — the identity the cache reads
    /// are keyed by, so both entry points land on the same movement.
    let id: String
    /// The title as the source spells it, shown until the read returns.
    let title: String
    /// Derived from the title, like everywhere else in the app.
    let muscleGroup: MuscleGroup
}

extension ExerciseSummary {
    var identity: ExerciseIdentity {
        ExerciseIdentity(id: id, title: title, muscleGroup: muscleGroup)
    }
}

extension ExerciseDetail {
    /// The same identity the exercise list hands out for this movement.
    ///
    /// Goes through `ExerciseSummary.key(templateID:title:)` rather than
    /// folding the title here: the key prefers the source's template id
    /// wherever there is one, and a title-only key would miss every movement
    /// that carries one — the progression screen would answer "not in this
    /// window" for an exercise the user is looking at.
    var identity: ExerciseIdentity {
        ExerciseIdentity(
            id: ExerciseSummary.key(templateID: templateID, title: title),
            title: title,
            muscleGroup: muscleGroup
        )
    }
}
