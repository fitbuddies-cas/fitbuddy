import SwiftUI

/// The training profile, editable after onboarding (US-13 AC5, #191).
///
/// The two questions from step 4, minus the step indicator and the skip
/// button — neither means anything in Settings. What it has instead is a way
/// to remove the profile, because a goal that was true three months ago is a
/// goal the recommendation should stop hearing about.
struct TrainingProfileSettingsView: View {
    @StateObject private var viewModel: TrainingProfileSettingsViewModel

    /// - Parameter viewModel: Built lazily — the autoclosure is evaluated once,
    ///   when SwiftUI first creates the view's state.
    init(viewModel: @autoclosure @escaping () -> TrainingProfileSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Used to tailor your AI analysis. Changes apply to the next analysis you run.")
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInkSecondary)

                section(title: "Goal") {
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        TrainingProfileOptionRow(
                            title: goal.displayName,
                            isSelected: viewModel.goal == goal
                        ) {
                            Task { await viewModel.select(goal: goal) }
                        }
                        .accessibilityIdentifier(AccessibilityID.TrainingProfile.goalOption(goal.rawValue))
                    }
                }

                section(title: "Strength training experience") {
                    ForEach(TrainingExperience.allCases, id: \.self) { experience in
                        TrainingProfileOptionRow(
                            title: experience.displayName,
                            isSelected: viewModel.experience == experience
                        ) {
                            Task { await viewModel.select(experience: experience) }
                        }
                        .accessibilityIdentifier(
                            AccessibilityID.TrainingProfile.experienceOption(experience.rawValue)
                        )
                    }
                }

                removeButton
                    .padding(.top, 28)
            }
            .padding(20)
        }
        .background(Color.fbBackground)
        .navigationTitle("Training profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            FBCard(padding: 0) {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
        .padding(.top, 22)
    }

    /// No confirmation dialog, unlike the key deletions on the screen before:
    /// a profile is two taps to restore, a key is a trip to another website.
    private var removeButton: some View {
        Button(role: .destructive) {
            Task { await viewModel.remove() }
        } label: {
            Text("Remove profile")
        }
        .buttonStyle(.fb(.danger))
        .disabled(!viewModel.hasProfile)
        .accessibilityIdentifier(AccessibilityID.TrainingProfile.removeButton)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TrainingProfileSettingsView(viewModel: TrainingProfileSettingsViewModel())
    }
}
#endif
