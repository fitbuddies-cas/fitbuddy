import SwiftUI

/// Onboarding step 2 (US-4): optionally enter the Claude API key. Mirrors the
/// layout of `HevyKeyEntryView` (step indicator, where-to-find card, monospaced
/// key field), but the key is optional — a prominent "Skip" CTA (AC2) sits
/// alongside "Save & continue" and there is no live key validation.
struct ClaudeKeyEntryView: View {
    @ObservedObject var viewModel: ClaudeKeyEntryViewModel

    private var isSaving: Bool { viewModel.state == .saving }

    private var failure: ClaudeKeyEntryState.Failure? {
        if case .failed(let failure) = viewModel.state { return failure }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                stepIndicator
                    .padding(.bottom, 22)
                Text("Connect Claude")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.fbInk)
                Text("Add your Claude API key to unlock AI training analysis, or skip this for now — you can add it later.")
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInkSecondary)
                    .padding(.top, 8)
                whereToFindCard
                    .padding(.top, 18)
                keyInput
                    .padding(.top, 22)
                storageNote
                    .padding(.top, 10)
                if let failure {
                    errorBanner(for: failure)
                        .padding(.top, 18)
                }
            }
            .padding(20)
        }
        .background(Color.fbBackground)
        .safeAreaInset(edge: .bottom) { ctaButtons.padding(16) }
        .animation(.easeOut(duration: 0.15), value: viewModel.state)
    }

    // MARK: - Sections

    /// Three-segment progress bar; this screen is always step 2 of 3.
    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index <= 1 ? Color.fbInk : Color.fbBorder)
                    .frame(height: 3)
            }
            Text("Step 2 of 3")
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
                .padding(.leading, 8)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Onboarding step 2 of 3")
    }

    /// Explains where the key lives in the Anthropic console.
    private var whereToFindCard: some View {
        HStack(alignment: .top, spacing: 12) {
            screenshotPlaceholder
            VStack(alignment: .leading, spacing: 6) {
                Text("Log in at **console.anthropic.com**, open **Settings → API Keys**, and tap **Create Key**.")
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
                Link(destination: ClaudeKeyEntryViewModel.anthropicConsoleURL) {
                    Text("Open console.anthropic.com ↗")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.fbAccent)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fbCardSubtle)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
        .overlay(
            RoundedRectangle(cornerRadius: FBRadius.control)
                .strokeBorder(Color.fbBorder, lineWidth: 1)
        )
    }

    private var screenshotPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.fbCard)
            .frame(width: 56, height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.fbTertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.fbMuted)
            )
            .accessibilityHidden(true)
    }

    private var keyInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLAUDE API KEY")
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: 14))
                    .foregroundStyle(viewModel.apiKey.isEmpty ? Color.fbMuted : Color.fbInkSecondary)
                TextField("sk-ant-…", text: $viewModel.apiKey)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Color.fbInk)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.go)
                    .disabled(isSaving)
                    .onSubmit { Task { await viewModel.save() } }
                if isSaving {
                    FBSpinner(size: 18, color: .fbMuted)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(Color.fbCard)
            .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
            .overlay(
                RoundedRectangle(cornerRadius: FBRadius.control)
                    .strokeBorder(inputBorderColor, lineWidth: inputBorderWidth)
            )
        }
    }

    private var inputBorderColor: Color {
        if failure == .keychain { return .fbRed }
        return viewModel.apiKey.isEmpty ? .fbBorder : .fbInk
    }

    private var inputBorderWidth: CGFloat {
        if failure == .keychain { return 2 }
        return viewModel.apiKey.isEmpty ? 1 : 1.5
    }

    private var storageNote: some View {
        Label("Stored in Apple Keychain · this device only · optional", systemImage: "lock")
            .font(.caption)
            .foregroundStyle(Color.fbMuted)
            .padding(.leading, 2)
    }

    private func errorBanner(for failure: ClaudeKeyEntryState.Failure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Could not save your key")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbRed)
            Text("The key could not be stored on this device. Please try again.")
                .font(.footnote)
                .foregroundStyle(Color.fbInkSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fbRedSoft)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
        .overlay(
            RoundedRectangle(cornerRadius: FBRadius.control)
                .strokeBorder(Color.fbRedBorder, lineWidth: 1)
        )
    }

    /// Save (primary) and Skip (prominent secondary, AC2) side by side.
    private var ctaButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await viewModel.save() }
            } label: {
                Text(saveButtonTitle)
            }
            .buttonStyle(.fb(.primary))
            .disabled(!viewModel.canSave)

            Button {
                viewModel.skip()
            } label: {
                Text("Skip for now")
            }
            .buttonStyle(.fb(.secondary))
            .disabled(isSaving)
        }
    }

    private var saveButtonTitle: String {
        isSaving ? "Saving…" : "Save & continue"
    }
}

#Preview {
    ClaudeKeyEntryView(viewModel: ClaudeKeyEntryViewModel())
}
