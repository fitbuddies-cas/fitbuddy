import SwiftUI

/// A single training session with everything the cache holds about it: the
/// header figures, then one card per exercise with its sets (US-2 AC1, #98).
///
/// Pushed from the dashboard's session list. Reads the local cache only — no
/// sync happens here, so going back costs nothing and the screen works offline
/// exactly as it does online.
struct WorkoutDetailView: View {
    @StateObject private var viewModel: WorkoutDetailViewModel

    /// - Parameter viewModel: Built lazily — the autoclosure is evaluated
    ///   once, when SwiftUI first creates the view's state, so the
    ///   `navigationDestination` closure does not rebuild it on every render.
    init(viewModel: @autoclosure @escaping () -> WorkoutDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.fbBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    /// The bar title stays generic until the session is loaded: naming it
    /// "Workout" and then swapping in the real title mid-render is less
    /// jarring than a title that appears out of nothing.
    private var title: String {
        if case .loaded(let detail) = viewModel.state { return detail.title }
        return "Workout"
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            FBSpinner()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        case .loaded(let detail):
            header(detail)
            ForEach(detail.exercises) { exercise in
                ExerciseDetailCard(exercise: exercise, sessionVolumeKg: detail.volumeKg)
            }
            if detail.exercises.isEmpty {
                emptyExercisesView
            }
        case .missing:
            missingView
        case .failed:
            failureView
        }
    }

    // MARK: - Header

    private func header(_ detail: WorkoutDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FBCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(detail.startTime, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.fbLabel)
                        .tracking(0.6)
                        .foregroundStyle(Color.fbMuted)
                    Text(detail.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.fbInk)
                    FBStat(
                        label: "Volume",
                        value: VolumeFormatter.full(detail.volumeKg),
                        unit: "kg"
                    )
                    Text(figures(detail))
                        .font(.footnote)
                        .fbTabularNumbers()
                        .foregroundStyle(Color.fbInkSecondary)
                }
            }
            if let description = detail.workoutDescription, !description.isEmpty {
                FBCard(padding: 16) {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Color.fbInkSecondary)
                }
            }
        }
    }

    /// `"6 exercises · 21 sets · 1 h 12 min"` — the duration only for a session
    /// Hevy actually closed.
    private func figures(_ detail: WorkoutDetail) -> String {
        [
            CountFormatter.labelled(detail.exerciseCount, singular: "exercise"),
            CountFormatter.labelled(detail.countedSetCount, singular: "set"),
            WorkoutDurationFormatter.session(from: detail.startTime, to: detail.endTime),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    // MARK: - The other three states

    /// A session whose exercises Hevy never received. Distinct from `.missing`:
    /// the session is cached, it simply holds nothing.
    private var emptyExercisesView: some View {
        FBCard(padding: 18) {
            FBInfoRow(
                icon: "list.bullet",
                title: "No exercises logged",
                text: "This session was recorded in Hevy without any exercises."
            )
        }
    }

    /// The window was replaced by a sync while this screen was open — the
    /// session is gone from the cache, and there is nothing here to fix.
    private var missingView: some View {
        FBCard(padding: 18) {
            FBInfoRow(
                icon: "clock.arrow.circlepath",
                title: "This session is no longer in your Hevy data",
                text: """
                It was removed the last time FitBuddy synced — either deleted in \
                Hevy or older than the 90 days the app keeps.
                """
            )
        }
        .padding(.top, 40)
    }

    /// The cache could not be read. Same wording as the dashboard's own
    /// failure card: it is the same store and the same remedy.
    private var failureView: some View {
        FBCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                FBInfoRow(
                    icon: "exclamationmark.triangle",
                    title: "This session could not be read",
                    text: """
                    The local cache on this device is unavailable. Going back and \
                    opening the session again usually helps — if it does not, \
                    restarting FitBuddy does.
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
#Preview("Loaded") {
    NavigationStack {
        WorkoutDetailView(
            viewModel: WorkoutDetailViewModel(
                cache: PreviewWorkoutDetailCache.filled,
                workoutID: PreviewWorkoutDetailCache.session.id
            )
        )
    }
}

#Preview("No longer cached") {
    NavigationStack {
        WorkoutDetailView(
            viewModel: WorkoutDetailViewModel(
                cache: PreviewWorkoutDetailCache.filled,
                workoutID: "gone"
            )
        )
    }
}

#Preview("Cache unavailable") {
    NavigationStack {
        WorkoutDetailView(
            viewModel: WorkoutDetailViewModel(
                cache: PreviewWorkoutDetailCache.failing,
                workoutID: PreviewWorkoutDetailCache.session.id
            )
        )
    }
}
#endif
