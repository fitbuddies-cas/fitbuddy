import Foundation

/// One movement of the cached window, folded over every session it appears in
/// — the `Sendable` row behind the exercise list (US-7, #37).
///
/// The counterpart to `ExerciseDetail`, which is one exercise inside one
/// session. The list answers a different question ("what have I trained, and
/// when did I last do it?"), so it needs the movement rolled up across the
/// window rather than ninety separate entries with the same title.
struct ExerciseSummary: Hashable, Identifiable, Sendable {
    /// Hevy's `exercise_template_id` when the cache holds one, otherwise the
    /// title folded for comparison — see `ExerciseSummary.key(templateID:title:)`.
    let id: String
    /// The title as Hevy spells it, taken from the most recent session the
    /// movement appears in: a user who renames an exercise means the new name.
    let title: String
    /// Derived from the title, like everywhere else in the app — v0 does not
    /// fetch Hevy's exercise templates (see `MuscleGroup`).
    let muscleGroup: MuscleGroup
    /// Sessions in the window that contained this movement.
    let sessionCount: Int
    /// Sets that counted towards `volumeKg` (warm-ups excluded).
    let countedSetCount: Int
    /// Σ (weight × reps) over the counted sets of every session, in kg.
    let volumeKg: Double
    /// Start of the most recent session containing this movement.
    let lastPerformed: Date
}

extension ExerciseSummary {
    /// Identity of a movement across sessions.
    ///
    /// `templateID` is Hevy's own stable id and wins whenever the cache holds
    /// one. Falling back to the folded title is what keeps the list from
    /// splitting "Bench Press (Barbell)" into two rows because one session was
    /// logged before the template id was cached — case and diacritics are
    /// folded so a user-created duplicate spelled differently still merges.
    static func key(templateID: String?, title: String) -> String {
        if let templateID, !templateID.isEmpty { return templateID }
        return title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
