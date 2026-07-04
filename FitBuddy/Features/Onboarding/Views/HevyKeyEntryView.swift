import SwiftUI

/// Onboarding step 1 (US-4): enter and verify the Hevy API key. Mirrors
/// `FBKeyEntryScreen` in `design/fb-screens.jsx` — step indicator, where-to-find
/// card, monospaced key field with inline spinner, error banner with a direct
/// link to Hevy's API settings, and a bottom CTA.
struct HevyKeyEntryView: View {
    @ObservedObject var viewModel: HevyKeyEntryViewModel
    @FocusState private var keyFieldIsFocused: Bool

    private var isValidating: Bool { viewModel.state == .validating }

    private var failure: HevyKeyEntryState.Failure? {
        if case .failed(let failure) = viewModel.state { return failure }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                stepIndicator
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

    /// Three-segment progress bar; this screen is always step 1 of 3.
    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index == 0 ? Color.fbInk : Color.fbBorder)
                    .frame(height: 3)
            }
            Text("Step 1 of 3")
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
                .padding(.leading, 8)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Onboarding step 1 of 3")
    }

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
        VStack(alignment: .leading, spacing: 8) {
            Text("HEVY API KEY")
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: 14))
                    .foregroundStyle(viewModel.apiKey.isEmpty ? Color.fbMuted : Color.fbInkSecondary)
                TextField("hv_live_…", text: $viewModel.apiKey)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Color.fbInk)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.go)
                    .focused($keyFieldIsFocused)
                    .disabled(isValidating)
                    .onSubmit { Task { await viewModel.connect() } }
                if isValidating {
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
        if failure == .invalidKey { return .fbRed }
        return viewModel.apiKey.isEmpty ? .fbBorder : .fbInk
    }

    private var inputBorderWidth: CGFloat {
        if failure == .invalidKey { return 2 }
        return viewModel.apiKey.isEmpty ? 1 : 1.5
    }

    private var storageNote: some View {
        Label("Stored in Apple Keychain · this device only", systemImage: "lock")
            .font(.caption)
            .foregroundStyle(Color.fbMuted)
            .padding(.leading, 2)
    }

    /// Failure banner (AC3): explains what went wrong and, for a rejected key,
    /// links straight to Hevy's API-key page.
    private func errorBanner(for failure: HevyKeyEntryState.Failure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bannerTitle(for: failure))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbRed)
            Text(bannerMessage(for: failure))
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
                .strokeBorder(Color.fbRed.opacity(0.2), lineWidth: 1)
        )
    }

    private func bannerTitle(for failure: HevyKeyEntryState.Failure) -> String {
        switch failure {
        case .invalidKey: return "Hevy rejected this key (HTTP 401)"
        case .network: return "Could not reach Hevy"
        case .keychain: return "Could not save your key"
        }
    }

    private func bannerMessage(for failure: HevyKeyEntryState.Failure) -> String {
        switch failure {
        case .invalidKey:
            return "The key may be revoked or mistyped. Generate a new one on hevy.com (Settings → Developer), then paste it here."
        case .network:
            return "Check your internet connection and try again."
        case .keychain:
            return "The key could not be stored on this device. Please try again."
        }
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
