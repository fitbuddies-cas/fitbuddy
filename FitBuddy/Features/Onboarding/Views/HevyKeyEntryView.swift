import SwiftUI

/// Onboarding step 2 (US-4): enter and verify the Hevy API key. Mirrors
/// `FBKeyEntryScreen` in `design/fb-screens.jsx` — step indicator, where-to-find
/// card, monospaced key field with inline spinner, error banner with a direct
/// link to Hevy's API settings, and a bottom CTA.
struct HevyKeyEntryView: View {
    @ObservedObject var viewModel: HevyKeyEntryViewModel
    @FocusState private var keyFieldIsFocused: Bool

    private var isValidating: Bool { viewModel.state == .validating }

    private var failure: APIKeyEntryFailure? {
        if case .failed(let failure) = viewModel.state { return failure }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FBStepIndicator(current: 2)
                    .padding(.bottom, 22)
                Text("Connect Hevy")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.fbInk)
                Text("Paste the API key from your Hevy account. We'll verify it before saving.")
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
        .safeAreaInset(edge: .bottom) { ctaButton.padding(16) }
        .animation(.easeOut(duration: 0.15), value: viewModel.state)
    }

    // MARK: - Sections

    /// Explains where the key lives in Hevy (AC1). The dashed box is a
    /// placeholder for the Hevy settings screenshot, as in the design mock.
    private var whereToFindCard: some View {
        HStack(alignment: .top, spacing: 12) {
            screenshotPlaceholder
            VStack(alignment: .leading, spacing: 6) {
                Text("The key is not available in the Hevy app — only on the Hevy website. Log in at **hevy.com**, open **Settings → Developer**, and tap **Generate API key**.")
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
                Link(destination: HevyKeyEntryViewModel.hevyAPISettingsURL) {
                    Text("Open hevy.com ↗")
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
                Image(systemName: "key.horizontal")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.fbMuted)
            )
            .accessibilityHidden(true)
    }

    private var keyInput: some View {
        FBKeyField(
            label: "HEVY API KEY",
            placeholder: HevyAPIKey.keyPlaceholder,
            text: $viewModel.apiKey,
            isBusy: isValidating,
            hasError: failure == .invalidKey,
            focus: $keyFieldIsFocused
        ) {
            Task { await viewModel.connect() }
        }
    }

    private var storageNote: some View {
        Label("Stored in Apple Keychain · this device only", systemImage: "lock")
            .font(.caption)
            .foregroundStyle(Color.fbMuted)
            .padding(.leading, 2)
    }

    /// Failure banner (AC3): explains what went wrong and, for a rejected key,
    /// links straight to Hevy's API-key page. The copy lives on
    /// `APIKeyEntryFailure` so the settings key editor (#83) says the same thing.
    private func errorBanner(for failure: APIKeyEntryFailure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(failure.title(for: "Hevy"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbRed)
            Text(failure.message(for: "Hevy"))
                .font(.footnote)
                .foregroundStyle(Color.fbInkSecondary)
            if failure == .invalidKey {
                Link(destination: HevyKeyEntryViewModel.hevyAPISettingsURL) {
                    Text("Open hevy.com API settings ↗")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.fbRed)
                }
                .padding(.top, 6)
            }
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

    private var ctaButton: some View {
        Button {
            if failure == .invalidKey {
                viewModel.retry()
                keyFieldIsFocused = true
            } else {
                Task { await viewModel.connect() }
            }
        } label: {
            Text(ctaTitle)
        }
        .buttonStyle(.fb(failure == .invalidKey ? .danger : .primary))
        .disabled(!viewModel.canConnect)
    }

    private var ctaTitle: String {
        if isValidating { return "Verifying with Hevy…" }
        if failure == .invalidKey { return "Try again" }
        return "Verify & continue"
    }
}

#Preview {
    HevyKeyEntryView(viewModel: HevyKeyEntryViewModel())
}
