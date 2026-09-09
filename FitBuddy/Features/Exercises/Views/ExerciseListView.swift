import SwiftUI

/// Every movement of the cached 90-day window, searchable by title
/// (US-7 AC1, #37).
///
/// Renders `ExerciseListViewModel`'s state and nothing else. The list is a
/// pure cache read — the dashboard owns the sync, so opening this screen never
/// costs a Hevy request.
///
/// The muscle-group filter (US-7 AC2) is not here yet; it is the next task on
/// the same story (#38) and hangs off the same view model.
struct ExerciseListView: View {
    @StateObject private var viewModel: ExerciseListViewModel

    /// - Parameter viewModel: Built lazily — the autoclosure is evaluated once,
    ///   when SwiftUI first creates the view's state.
    init(viewModel: @autoclosure @escaping () -> ExerciseListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
        }
        .background(Color.fbBackground)
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        // The system field, not one of our own: it filters while typing (AC1)
        // and brings the placement, the cancel button and the Dynamic Type
        // behaviour the user already knows from every other iOS list.
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            FBSpinner()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        case .loaded:
            if viewModel.hasNoSearchMatches {
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
                    ExerciseSummaryRow(exercise: exercise)
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

    /// The query matched nothing (AC1). A statement about the search, which is
    /// why it names the query and offers no retry — the fix is to type less.
    private var noMatchesView: some View {
        FBCard(padding: 18) {
            FBInfoRow(
                icon: "magnifyingglass",
                title: "No exercises found",
                text: "Nothing in the last 90 days matches your search. Try a shorter term."
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
        ExerciseListView(viewModel: ExerciseListViewModel(cache: PreviewExerciseCache.filled))
    }
}

#Preview("Empty") {
    NavigationStack {
        ExerciseListView(viewModel: ExerciseListViewModel(cache: PreviewExerciseCache.empty))
    }
}
#endif
