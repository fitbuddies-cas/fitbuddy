import SwiftUI

/// One movement's progression over the cached window (US-9, #42).
///
/// Named for what it shows rather than after the issue's `ExerciseDetailView`:
/// `ExerciseDetail` already means one exercise *inside one session* (#98), and
/// two screens whose names differ by a suffix while their subjects differ by a
/// dimension is how the wrong one gets opened.
struct ExerciseProgressionView: View {
    @StateObject private var viewModel: ExerciseProgressionViewModel

    /// - Parameter viewModel: Built lazily — the autoclosure is evaluated once,
    ///   when SwiftUI first creates the view's state.
    init(viewModel: @autoclosure @escaping () -> ExerciseProgressionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color.fbBackground)
        .navigationTitle(viewModel.exercise.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Sections

    /// Muscle group, title and — when the curve has stalled — the badge AC2
    /// asks for, next to the title rather than inside the chart: it is a
    /// statement about the movement, not about a data point.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.exercise.muscleGroup.displayName.uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(viewModel.exercise.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.fbInk)
                if viewModel.showsPlateauBadge {
                    plateauBadge
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// AC2's yellow label. It says what it means rather than only "Plateau":
    /// the badge is the first thing read, and a single word invites the guess
    /// that something is broken.
    private var plateauBadge: some View {
        Text("Plateau")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.fbWarn)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.fbWarnSoft)
            .clipShape(Capsule())
            .accessibilityLabel("Plateau: no new best in the last three sessions")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            FBSpinner()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        case .loaded(let progression):
            ProgressionChartCard(points: progression.points)
            summaryCard(for: progression)
            if viewModel.showsPlateauBadge {
                plateauExplanation
            }
        case .insufficientData:
            insufficientDataView
        case .unavailable:
            unavailableView
        case .failed:
            failureView
        }
    }

    /// The two numbers the curve is read for, spelled out — a chart answers
    /// "which way" well and "how much exactly" badly.
    private func summaryCard(for progression: ExerciseProgression) -> some View {
        FBCard(padding: 18) {
            HStack(alignment: .top, spacing: 16) {
                FBStat(
                    label: "Best",
                    value: OneRepMaxFormatter.kilograms(progression.bestEstimateKg ?? 0),
                    unit: "kg"
                )
                FBStat(
                    label: "Latest",
                    value: OneRepMaxFormatter.kilograms(progression.latestEstimateKg ?? 0),
                    unit: "kg"
                )
                FBStat(
                    label: "Sessions",
                    value: "\(progression.points.count)"
                )
            }
        }
    }

    /// Why the badge is there, and what it does not claim: three sessions are
    /// a hint, not a diagnosis.
    private var plateauExplanation: some View {
        FBCard(padding: 18) {
            FBInfoRow(
                icon: "chart.line.flattrend.xyaxis",
                title: "No new best in three sessions",
                text: """
                Your estimated one-rep max has not gone past its previous peak in the last three \
                sessions. That can mean a deload week, a change of rep range, or a plateau worth \
                acting on — the curve says it happened, not why.
                """
            )
        }
    }

    /// AC3: fewer than two sessions carry weight and reps, so there is no line
    /// to draw. The hint counts what is there, because "not enough" without a
    /// number leaves the user guessing how much is missing.
    private var insufficientDataView: some View {
        FBCard(padding: 18) {
            FBInfoRow(
                icon: "chart.xyaxis.line",
                title: "Not enough data yet",
                text: """
                \(viewModel.sessionsSoFarDescription) At least \
                \(ExerciseProgression.minimumPlottableSessions) sessions with weight and reps are \
                needed before a progression curve can be drawn.
                """
            )
        }
        .padding(.top, 28)
    }

    /// The cache was replaced while the screen was open — a new Hevy key drops
    /// the window under it (#91).
    private var unavailableView: some View {
        FBCard(padding: 18) {
            FBInfoRow(
                icon: "questionmark.circle",
                title: "Exercise not in this window",
                text: """
                This exercise is not part of the last \(TrainingWindow.days) days any more. Pull to \
                refresh on the dashboard to load the current window.
                """
            )
        }
        .padding(.top, 28)
    }

    private var failureView: some View {
        FBCard(padding: 18) {
            FBInfoRow(
                icon: "externaldrive.badge.exclamationmark",
                title: "Training data not readable",
                text: "The local training data could not be read. Restarting the app usually clears this."
            )
        }
        .padding(.top, 28)
    }
}

#if DEBUG
#Preview("Rising") {
    NavigationStack {
        ExerciseProgressionView(viewModel: PreviewProgressionCache.rising)
    }
}

#Preview("Plateau") {
    NavigationStack {
        ExerciseProgressionView(viewModel: PreviewProgressionCache.plateaued)
    }
}

#Preview("Too little data") {
    NavigationStack {
        ExerciseProgressionView(viewModel: PreviewProgressionCache.sparse)
    }
}
#endif
