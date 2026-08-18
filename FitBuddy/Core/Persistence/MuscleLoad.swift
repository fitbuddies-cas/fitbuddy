import Foundation

/// How much of a window's training load fell on one muscle group — the data
/// behind the dashboard's distribution chart (US-2 AC1, #27).
struct MuscleLoad: Equatable, Identifiable, Sendable {
    let group: MuscleGroup
    /// Σ (weight × reps) over the group's counted sets, in kg.
    let volumeKg: Double
    /// Counted sets (warm-ups excluded) that loaded the group. Carries the
    /// groups that produce no kg volume at all — planks, pull-ups, cardio.
    let setCount: Int

    var id: MuscleGroup { group }
}

extension MuscleLoad {
    /// Sums loads of the same group and returns them heaviest first.
    ///
    /// Ties break on the group's declaration order, so a chart of equal bars
    /// keeps a stable row order between reads instead of reshuffling.
    static func merged(_ loads: [MuscleLoad]) -> [MuscleLoad] {
        var volumes: [MuscleGroup: Double] = [:]
        var sets: [MuscleGroup: Int] = [:]
        for load in loads {
            volumes[load.group, default: 0] += load.volumeKg
            sets[load.group, default: 0] += load.setCount
        }

        return MuscleGroup.allCases
            .filter { sets[$0] != nil }
            .map { MuscleLoad(group: $0, volumeKg: volumes[$0] ?? 0, setCount: sets[$0] ?? 0) }
            .sorted { lhs, rhs in
                lhs.volumeKg == rhs.volumeKg
                    ? order(of: lhs.group) < order(of: rhs.group)
                    : lhs.volumeKg > rhs.volumeKg
            }
    }

    private static func order(of group: MuscleGroup) -> Int {
        MuscleGroup.allCases.firstIndex(of: group) ?? MuscleGroup.allCases.count
    }
}
