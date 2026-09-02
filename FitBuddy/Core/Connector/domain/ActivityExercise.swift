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
    var sets: [ActivityExerciseSet]

    var id: Int { index }

    init(
        index: Int,
        title: String,
        notes: String? = nil,
        sets: [ActivityExerciseSet] = []
    ) {
        self.index = index
        self.title = title
        self.notes = notes
        self.sets = sets
    }
}
