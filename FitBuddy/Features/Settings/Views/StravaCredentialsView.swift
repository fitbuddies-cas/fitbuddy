import SwiftUI

/// Enter the client ID and client secret of the user's own Strava API
/// application (#139, US-5 AC3). Same shape as `HevyKeyEntryView` and
/// `KeyEditorSheet`: where-to-find card, key fields, Keychain storage note,
/// failure banner, bottom CTA — pushed from Settings rather than presented as
/// a sheet, because the connection screen (#140) links here too.
///
/// The fields always start empty. A stored pair is shown as the client ID
/// plus a masked secret, so the user can tell whether saving replaces
/// something without the secret ever being displayed.
struct StravaCredentialsView: View {
    @StateObject private var viewModel: StravaCredentialsViewModel
    @Environment(\.dismiss) private var dismiss
    // Two booleans rather than one optional enum: `FBKeyField` binds a
    // `FocusState<Bool>`, and a `FocusState<Field?>` cannot be projected onto
    // one field's yes/no.
    @FocusState private var clientIDIsFocused: Bool
    @FocusState private var clientSecretIsFocused: Bool

    /// - Parameter viewModel: Built lazily — the autoclosure is evaluated once,
    ///   when SwiftUI first creates the view's state, so a `NavigationLink`
    ///   holding this view does not build a view model until it is pushed.
    init(viewModel: @autoclosure @escaping () -> StravaCredentialsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    private var isSaving: Bool { viewModel.state == .saving }

    private var failure: APIKeyEntryFailure? {
        if case .failed(let failure) = viewModel.state { return failure }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInkSecondary)
                whereToFindCard
                    .padding(.top, 18)
                if viewModel.hasStoredCredentials {
                    storedPair
                        .padding(.top, 18)
                }
                clientIDField
                    .padding(.top, 22)
                clientSecretField
                    .padding(.top, 16)
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
        .navigationTitle("\(StravaKeyPresentation.displayName) API application")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { saveButton.padding(16) }
        .animation(.easeOut(duration: 0.15), value: viewModel.state)
        .task { await viewModel.bootstrap() }
        // Saved is the end of this screen: the caller — Settings or the
        // connection screen — is where the next step happens.
        .onChange(of: viewModel.state) { _, state in
            if state == .saved { dismiss() }
        }
        // The banner has something to read and the keyboard would cover it.
        .onChange(of: failure) { _, failure in
            if failure != nil {
                clientIDIsFocused = false
                clientSecretIsFocused = false
            }
        }
    }

    // MARK: - Copy

    private var subtitle: String {
        if viewModel.hasStoredCredentials {
            return "Enter a new client ID and secret to replace the stored pair. Reconnect afterwards — the existing connection stays tied to the old application."
        }
        return "FitBuddy talks to Strava through an API application that belongs to you. Create one and paste its credentials here."
    }

    // MARK: - Sections

    private var whereToFindCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(.markdownOrPlain(StravaKeyPresentation.consoleInstructions))
                .font(.footnote)
                .foregroundStyle(Color.fbInkSecondary)
            Link(destination: StravaKeyPresentation.consoleURL) {
                Text("Open \(StravaKeyPresentation.consoleName) ↗")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.fbAccent)
            }
            NavigationLink {
                StravaSetupGuideView()
            } label: {
                Text("Read the step-by-step setup guide →")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.fbAccent)
            }
            .accessibilityIdentifier(AccessibilityID.StravaCredentials.setupGuideLink)
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

    /// What is stored right now. The secret is only ever shown masked (#83).
    private var storedPair: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 16))
                .foregroundStyle(Color.fbAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stored application")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.fbInk)
                Text("Client ID \(viewModel.storedClientID ?? "") · secret \(viewModel.storedSecretMask ?? "")")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.fbInkSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fbCard)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
        .overlay(
            RoundedRectangle(cornerRadius: FBRadius.control)
                .strokeBorder(Color.fbBorder, lineWidth: 1)
        )
    }

    private var clientIDField: some View {
        FBKeyField(
            label: "CLIENT ID",
            placeholder: StravaKeyPresentation.clientIDPlaceholder,
            text: $viewModel.clientID,
            isBusy: isSaving,
            focus: $clientIDIsFocused,
            identifier: AccessibilityID.StravaCredentials.clientIDField
        ) {
            // "Go" on the first field moves on to the second.
            clientSecretIsFocused = true
        }
    }

    private var clientSecretField: some View {
        FBKeyField(
            label: "CLIENT SECRET",
            placeholder: StravaKeyPresentation.clientSecretPlaceholder,
            text: $viewModel.clientSecret,
            isBusy: isSaving,
            focus: $clientSecretIsFocused,
            identifier: AccessibilityID.StravaCredentials.clientSecretField
        ) {
            Task { await viewModel.save() }
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
            Text(failure.title(for: StravaKeyPresentation.displayName))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbRed)
            Text(failure.message(for: StravaKeyPresentation.displayName))
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.StravaCredentials.errorBanner)
    }

    private var saveButton: some View {
        Button {
            Task { await viewModel.save() }
        } label: {
            Text(saveButtonTitle)
        }
        .buttonStyle(.fb(.primary))
        .disabled(!viewModel.canSave)
        .accessibilityIdentifier(AccessibilityID.StravaCredentials.saveButton)
    }

    private var saveButtonTitle: String {
        if isSaving { return "Saving…" }
        return viewModel.hasStoredCredentials ? "Replace credentials" : "Save credentials"
    }
}

#Preview {
    NavigationStack {
        StravaCredentialsView(viewModel: StravaCredentialsViewModel())
    }
}
