import SwiftUI

/// Every movement of the cached 90-day window, searchable by title
/// (US-7 AC1, #37).
///
/// Renders `ExerciseListViewModel`'s state and nothing else. The list is a
/// pure cache read — the dashboard owns the sync, so opening this screen never
/// costs a Hevy request.
///
/// The muscle-group filter (US-7 AC2) sits above the list as `ExerciseFilterView`
/// and combines with the search field (AC3); both hang off the same view model.
struct ExerciseListView: View {
    @StateObject private var viewModel: ExerciseListViewModel
    private let makeProgressionViewModel: (ExerciseSummary) -> ExerciseProgressionViewModel

    /// - Parameters:
    ///   - viewModel: Built lazily — the autoclosure is evaluated once, when
    ///     SwiftUI first creates the view's state.
    ///   - makeProgressionViewModel: Called once per pushed movement, not once
    ///     per rendered row — see `.navigationDestination` below (#42).
    init(
        viewModel: @autoclosure @escaping () -> ExerciseListViewModel,
        makeProgressionViewModel: @escaping (ExerciseSummary) -> ExerciseProgressionViewModel
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.makeProgressionViewModel = makeProgressionViewModel
    }

    var body: some View {
        scrollView
            .background(Color.fbBackground)
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            // By value, so the destination is built when a row is tapped
            // rather than once per row while the list renders (#42).
            .navigationDestination(for: ExerciseSummary.self) { exercise in
                ExerciseProgressionView(viewModel: makeProgressionViewModel(exercise))
            }
            .task { await viewModel.load() }
    }

    /// The search field is attached only once the window has loaded with
    /// movements in it — over an empty or failed window it would be a control
    /// with nothing to filter.
    ///
    /// The system field, not one of our own: it filters while typing (AC1) and
    /// brings the placement, the cancel button and the Dynamic Type behaviour
    /// the user already knows from every other iOS list.
    @ViewBuilder
    private var scrollView: some View {
        if viewModel.showsFilterControls {
            baseScrollView
                .searchable(
                    text: $viewModel.searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search exercises"
                )
        } else {
            baseScrollView
        }
    }

    private var baseScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterRow
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
        }
    }

    /// The muscle-group chips (AC2), edge-to-edge so they scroll under the
    /// screen margin. Only over a loaded window with movements in it — the same
    /// condition as the search field.
    @ViewBuilder
    private var filterRow: some View {
        if viewModel.showsFilterControls {
            ExerciseFilterView(
                groups: viewModel.filterGroups,
                selection: viewModel.selectedMuscleGroups,
                onToggle: { viewModel.toggle($0) }
            )
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            FBSpinner()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        case .loaded:
            if viewModel.hasNoMatches {
                noMatchesView
            } else {
                list
            }
        case .empty:
            emptyView
        case .failed:
            failureView
        }
    }

    private var list: some View {
        FBCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(viewModel.visibleExercises.enumerated()), id: \.element.id) { index, exercise in
                    if index > 0 {
                        Divider().overlay(Color.fbDivider)
                    }
                    NavigationLink(value: exercise) {
                        ExerciseSummaryRow(exercise: exercise)
                    }
                    // The row paints itself; the link only makes it tappable.
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 12)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Last 90 days".uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            Spacer()
            // The visible count, not the window's total: while a search is
            // running the number has to describe the list under it.
            Text(CountFormatter.labelled(viewModel.visibleExercises.count, singular: "exercise"))
                .font(.caption2)
                .foregroundStyle(Color.fbMuted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    /// Search and/or muscle-group filter matched nothing (AC1/AC2). A statement
    /// about the filter, which is why it offers no retry — the fix is to widen
    /// the search term or drop a chip.
    private var noMatchesView: some View {
        FBCard(padding: 18) {
            FBInfoRow(
                icon: "line.3.horizontal.decrease",
                title: "No exercises found",
                text: "Nothing in the last 90 days matches your filter. Try a shorter term, or turn off a muscle group."
            )
        }
        .padding(.top, 40)
    }

    private var emptyView: some View {
        FBCard(padding: 18) {
            FBInfoRow(
                icon: "figure.strengthtraining.traditional",
                title: "No exercises yet",
                text: """
                Once your Hevy workouts have synced, every exercise from the last \
                90 days shows up here.
                """
            )
        }
        .padding(.top, 40)
    }

    private var failureView: some View {
        FBCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                FBInfoRow(
                    icon: "exclamationmark.triangle",
                    title: "Your exercises could not be read",
                    text: """
                    The local cache on this device is unavailable. Try again — \
                    if that does not help, restarting FitBuddy usually does.
                    """
                )
                Button("Try again") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(FBButtonStyle(kind: .secondary))
            }
        }
        .padding(.top, 40)
    }
}

#if DEBUG
#Preview("With data") {
    NavigationStack {
        ExerciseListView(
            viewModel: ExerciseListViewModel(cache: PreviewExerciseCache.filled),
            makeProgressionViewModel: { _ in PreviewProgressionCache.rising }
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        ExerciseListView(
            viewModel: ExerciseListViewModel(cache: PreviewExerciseCache.empty),
            makeProgressionViewModel: { _ in PreviewProgressionCache.rising }
        )
    }
}
#endif
