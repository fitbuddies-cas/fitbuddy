import SwiftUI

/// Sheet for adding or replacing one stored API key from Settings (#83).
///
/// Mirrors the onboarding key screens: `FBKeyField`, the Keychain storage note,
/// and the same failure banner copy (`APIKeyEntryFailure`). The field always
/// starts empty — the stored key is never displayed, so it cannot be pre-filled
/// either.
struct KeyEditorSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    let target: SettingsKeyTarget

    @FocusState private var keyFieldIsFocused: Bool

    private var isBusy: Bool { viewModel.editorState == .validating }

    private var failure: APIKeyEntryFailure? {
        if case .failed(let failure) = viewModel.editorState { return failure }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.fbInkSecondary)
                    if case .llm(let provider) = target {
                        whereToFindCard(for: provider)
                            .padding(.top, 18)
                    }
                    keyField
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { viewModel.cancelEditing() }
                        .foregroundStyle(Color.fbInk)
                        .disabled(isBusy)
                }
            }
            .safeAreaInset(edge: .bottom) { saveButton.padding(16) }
        }
        // A half-written key is cheap to retype; an interrupted Keychain write
        // is not, so only the in-flight save blocks the swipe-down.
        .interactiveDismissDisabled(isBusy)
        .animation(.easeOut(duration: 0.15), value: viewModel.editorState)
        .onAppear { keyFieldIsFocused = true }
    }

    // MARK: - Copy

    private var title: String {
        let verb = viewModel.isReplacing(target) ? "Replace" : "Add"
        return "\(verb) \(target.displayName) key"
    }

    private var subtitle: String {
        if target.isValidatedBeforeSaving {
            return "Paste the new key. We'll verify it with \(target.displayName) before it replaces the stored one."
        }
        return """
        Paste the key. It is stored as-is — there is no way to verify an AI provider key without \
        spending a request, so a wrong key only shows up at the next analysis.
        """
    }

    // MARK: - Sections

    /// Explains where the key lives in the provider's console — the same card
    /// onboarding step 3 shows, so a user replacing a key gets the same help.
    private func whereToFindCard(for provider: LLMProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(attributedInstructions(for: provider))
                .font(.footnote)
                .foregroundStyle(Color.fbInkSecondary)
            Link(destination: provider.consoleURL) {
                Text("Open \(provider.consoleName) ↗")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.fbAccent)
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

    private func attributedInstructions(for provider: LLMProvider) -> AttributedString {
        (try? AttributedString(markdown: provider.consoleInstructions))
            ?? AttributedString(provider.consoleInstructions)
    }

    private var keyField: some View {
        FBKeyField(
            label: "\(target.displayName.uppercased()) API KEY",
            placeholder: target.keyPlaceholder,
            text: $viewModel.editorKey,
            isBusy: isBusy,
            hasError: failure != nil,
            focus: $keyFieldIsFocused
        ) {
            Task { await viewModel.submitEditor() }
        }
    }

    private var storageNote: some View {
        Label("Stored in Apple Keychain · this device only", systemImage: "lock")
            .font(.caption)
            .foregroundStyle(Color.fbMuted)
            .padding(.leading, 2)
    }

    private func errorBanner(for failure: APIKeyEntryFailure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(failure.title(for: target.displayName))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbRed)
            Text(failure.message(for: target.displayName))
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

    private var saveButton: some View {
        Button {
            Task { await viewModel.submitEditor() }
        } label: {
            Text(saveButtonTitle)
        }
        .buttonStyle(.fb(.primary))
        .disabled(!viewModel.canSubmitEditor)
    }

    private var saveButtonTitle: String {
        guard isBusy else { return "Save key" }
        return target.isValidatedBeforeSaving ? "Verifying with \(target.displayName)…" : "Saving…"
    }
}
