import Foundation

extension ExerciseHistoryEntry {
    /// The session's sets that carry a working weight, in logged order.
    var workingSets: [WorkingSet] {
        sets.compactMap(WorkingSet.init(set:))
    }

    /// The session's working weight: its heaviest working set, ties broken by
    /// reps (#173). `nil` when no set carried both weight and reps.
    var heaviestWorkingSet: WorkingSet? {
        workingSets.max { $1.isHeavier(than: $0) }
    }
}
