import SwiftUI

/// Muscle-group filter for the exercise list: a horizontal row of chips, each
/// toggling one group in or out of the filter (US-7 AC2, #38).
///
/// Multi-select with OR semantics — Chest and Back together show movements for
/// either. Presentational only: the selection lives in `ExerciseListViewModel`
/// and combines with the search field there (AC3).
struct ExerciseFilterView: View {
    /// Every group offered as a chip, in the app's canonical order (AC1).
    let groups: [MuscleGroup]
    /// The groups currently switched on.
    let selection: Set<MuscleGroup>
    /// One chip tap — the view model flips the group in `selection`.
    let onToggle: (MuscleGroup) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups) { group in
                    Chip(
                        title: group.displayName,
                        isSelected: selection.contains(group),
                        action: { onToggle(group) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by muscle group")
    }

    /// One capsule chip. Selected reads as a filled `fbInk` pill (matching the
    /// primary button), unselected as a hairline-bordered `fbCardSubtle` pill
    /// (matching the secondary button).
    private struct Chip: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.fbLabel)
                    .tracking(0.3)
                    .foregroundStyle(isSelected ? Color.fbBackground : Color.fbInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(isSelected ? Color.fbInk : Color.fbCardSubtle)
                    .overlay(
                        Capsule().strokeBorder(Color.fbBorder, lineWidth: isSelected ? 0 : 1)
                    )
                    .clipShape(Capsule())
                    // The pill keeps its ~30 pt height; the hit target is padded
                    // out to the 44 pt HIG minimum without inflating the visual.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

#if DEBUG
private struct ExerciseFilterPreview: View {
    @State private var selection: Set<MuscleGroup> = [.chest, .back]

    var body: some View {
        ExerciseFilterView(
            groups: MuscleGroup.allCases,
            selection: selection,
            onToggle: { group in
                if selection.contains(group) {
                    selection.remove(group)
                } else {
                    selection.insert(group)
                }
            }
        )
        .background(Color.fbBackground)
    }
}

#Preview {
    ExerciseFilterPreview()
}
#endif
