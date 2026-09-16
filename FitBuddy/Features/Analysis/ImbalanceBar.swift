import Foundation

/// One muscle group's bar on the imbalance card (US-14, #177).
struct ImbalanceBar: Equatable, Sendable {
    let group: MuscleGroup
    let perWeek: Double
    /// Bar length in `0...1`, relative to the more frequent of the two groups.
    let share: Double

    /// The two bars of an imbalance card, the more frequent group first.
    ///
    /// Ordered by frequency rather than as the model named them, so the full
    /// bar always comes first and takes the progress colour, and the shorter
    /// one — the group the card is about — takes the warning colour, as in
    /// design 3.4. On a tie the model's order stays.
    ///
    /// The larger group fills its bar; the other is its fraction of it. When
    /// neither was trained there is nothing to compare, and both bars read
    /// empty rather than dividing by zero.
    static func bars(
        groupA: MuscleGroup,
        perWeekA: Double,
        groupB: MuscleGroup,
        perWeekB: Double
    ) -> [ImbalanceBar] {
        let largest = max(perWeekA, perWeekB)
        func share(_ perWeek: Double) -> Double {
            guard largest > 0, perWeek.isFinite, largest.isFinite else { return 0 }
            return min(max(perWeek / largest, 0), 1)
        }
        let a = ImbalanceBar(group: groupA, perWeek: perWeekA, share: share(perWeekA))
        let b = ImbalanceBar(group: groupB, perWeek: perWeekB, share: share(perWeekB))
        return perWeekB > perWeekA ? [b, a] : [a, b]
    }
}
