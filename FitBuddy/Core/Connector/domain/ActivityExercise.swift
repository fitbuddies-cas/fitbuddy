import Foundation

/// One exercise performed within an `Activity`, holding its logged sets.
struct ActivityExercise: Identifiable, Equatable, Codable, Sendable {
    /// Position of the exercise within the activity, as reported by the
    /// source. Doubles as the `Identifiable` id — it is derived from the
    /// source data and therefore stable across re-syncs, where a freshly
    /// generated `UUID()` per mapping would not be: it would make an
    /// unchanged workout compare `!=` to its cached copy and force SwiftUI
    /// to rebuild every `ForEach` row instead of diffing it.
    var index: Int
    var title: String
    var notes: String?
    /// The source's own identifier for the movement itself, stable across
    /// activities (Hevy's `exercise_template_id`). It is what per-exercise
    /// progression (US-9) matches on, where the title alone would split a
    /// movement the user renamed.
    var templateID: String?
    /// Grouping id for exercises the source reports as one superset; `nil`
    /// when the exercise stands alone or the source has no such concept.
    var supersetID: Int?
    var sets: [ActivityExerciseSet]

    var id: Int { index }

    init(
        index: Int,
        title: String,
        notes: String? = nil,
        templateID: String? = nil,
        supersetID: Int? = nil,
        sets: [ActivityExerciseSet] = []
    ) {
        self.index = index
        self.title = title
        self.notes = notes
        self.templateID = templateID
        self.supersetID = supersetID
        self.sets = sets
    }
}
