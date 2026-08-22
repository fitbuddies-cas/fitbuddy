import Foundation

/// One exercise performed within an `Activity`, holding its logged sets.
struct ActivityExercise: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    /// Position of the exercise within the activity, as reported by the source.
    var index: Int
    var title: String
    var notes: String?
    var sets: [ActivityExerciseSet]

    init(
        id: UUID = UUID(),
        index: Int,
        title: String,
        notes: String? = nil,
        sets: [ActivityExerciseSet] = []
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.notes = notes
        self.sets = sets
    }
}
