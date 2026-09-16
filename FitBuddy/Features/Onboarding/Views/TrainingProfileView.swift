import SwiftUI

/// Onboarding step 4 (US-13): what the user trains for, and how long they have
/// been lifting.
///
/// Two questions, both optional, and a way past them. The screen says what the
/// answers are for — a question whose purpose is unstated reads as data
/// collection, and this one is asked right after two API keys.
struct TrainingProfileView: View {
    @ObservedObject var viewModel: TrainingProfileViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FBStepIndicator(current: 4)
                    .padding(.bottom, 22)
                Text("What are you training for?")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.fbInk)
                Text("Used to tailor your AI analysis. Both questions are optional, and you can change your answers later in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInkSecondary)
                    .padding(.top, 8)

                section(title: "Goal") {
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        choice(
                            title: goal.displayName,
                            isSelected: viewModel.goal == goal,
                            identifier: AccessibilityID.TrainingProfile.goalOption(goal.rawValue)
                        ) {
                            // Tapping the selected option clears it: without
                            // that, a mis-tap is permanent for the rest of the
                            // step — there is no "none of these" row.
                            viewModel.goal = viewModel.goal == goal ? nil : goal
                        }
                    }
                }

                section(title: "Strength training experience") {
                    ForEach(TrainingExperience.allCases, id: \.self) { experience in
                        choice(
                            title: experience.displayName,
                            isSelected: viewModel.experience == experience,
                            identifier: AccessibilityID.TrainingProfile.experienceOption(experience.rawValue)
                        ) {
                            viewModel.experience = viewModel.experience == experience ? nil : experience
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.fbBackground)
        .safeAreaInset(edge: .bottom) { ctaButtons.padding(16) }
        .accessibilityIdentifier(AccessibilityID.TrainingProfile.root)
        .task { await viewModel.bootstrap() }
    }

    // MARK: - Sections

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

    private func choice(
        title: String,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        TrainingProfileOptionRow(title: title, isSelected: isSelected, action: action)
            .accessibilityIdentifier(identifier)
    }

    /// Confirm and skip, stacked as on step 3 — the same shape for the same
    /// choice, so the way past an optional step is where the user last saw it.
    private var ctaButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await viewModel.save() }
            } label: {
                Text("Save and continue")
            }
            .buttonStyle(.fb(.primary))
            .disabled(!viewModel.canSave)
            .accessibilityIdentifier(AccessibilityID.TrainingProfile.saveButton)

            Button {
                Task { await viewModel.skip() }
            } label: {
                Text("Skip for now")
            }
            .buttonStyle(.fb(.secondary))
            .accessibilityIdentifier(AccessibilityID.TrainingProfile.skipButton)
        }
    }
}

#if DEBUG
#Preview("Empty") {
    TrainingProfileView(viewModel: TrainingProfileViewModel())
}
#endif
