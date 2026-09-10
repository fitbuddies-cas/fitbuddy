import SwiftUI

/// Settings screen (#83): manage the stored API keys, reorder the LLM fallback
/// priority, read the privacy policy, and delete all local data.
///
/// A grouped `List` rather than the card stack the onboarding screens use —
/// drag-to-reorder (`.onMove`) only exists inside a `List`, and reordering the
/// providers is one of this screen's jobs. The design-system colors are applied
/// on top of it so it still reads as FitBuddy.
///
/// Its own tab in `MainTabView` (#107), so there is nothing to dismiss: a
/// deleted Hevy key or a full wipe drops the app into onboarding, which
/// replaces the tab bar altogether.
struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    private let makeStravaCredentialsViewModel: @MainActor () -> StravaCredentialsViewModel

    /// - Parameters:
    ///   - viewModel: Built lazily — the autoclosure is evaluated once, when
    ///     SwiftUI first creates the view's state, so presenting this from a
    ///     parent's `body` does not rebuild it on every render.
    ///   - makeStravaCredentialsViewModel: Called once per push of the Strava
    ///     credentials screen (#139).
    init(
        viewModel: @autoclosure @escaping () -> SettingsViewModel,
        makeStravaCredentialsViewModel: @escaping @MainActor () -> StravaCredentialsViewModel = { StravaCredentialsViewModel() }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.makeStravaCredentialsViewModel = makeStravaCredentialsViewModel
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color.fbBackground)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
        }
        .task { await viewModel.load() }
        .sheet(item: $viewModel.editorTarget) { target in
            KeyEditorSheet(viewModel: viewModel, target: target)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: viewModel.pendingDeletion
        ) { target in
            Button("Delete", role: .destructive) {
                Task { await viewModel.delete(target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text(deletionMessage(for: target))
        }
        .confirmationDialog(
            "Delete all data?",
            isPresented: $viewModel.isConfirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                Task { await viewModel.deleteAllData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
            This removes all API keys, your consent, the cached training data, the sync timestamp \
            and the provider order from this device. FitBuddy restarts at the beginning of onboarding.
            """)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            FBSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            failureView
        case .ready:
            settingsList
        }
    }

    private var settingsList: some View {
        List {
            if let actionError = viewModel.actionError {
                Section {
                    Text(actionError)
                        .font(.footnote)
                        .foregroundStyle(Color.fbRed)
                }
                .listRowBackground(Color.fbRedSoft)
            }
            hevySection
            llmSection
            privacySection
            dangerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// The stored keys could not be read. Kept distinct from "no keys stored":
    /// offering to add a key over one that may still be there would invite the
    /// user to overwrite it blindly.
    private var failureView: some View {
        FBCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                FBInfoRow(
                    icon: "exclamationmark.triangle",
                    title: "Your keys could not be read",
                    text: """
                    The Keychain on this device is currently unavailable — this can happen right \
                    after a restart, before the device has been unlocked once. Please try again.
                    """
                )
                Button("Try again") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.fb(.secondary))
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Sections

    private var hevySection: some View {
        Section {
            keyRow(
                title: SettingsKeyTarget.hevy.displayName,
                subtitle: viewModel.hevyKeyMask ?? "No key stored",
                isMasked: viewModel.hevyKeyMask != nil,
                target: .hevy,
                canDelete: viewModel.hevyKeyMask != nil
            )
            stravaRow
        } header: {
            Text("TRAINING DATA")
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
        } footer: {
            Text("""
            Replacing the Hevy key clears the cached workouts and syncs the new account's \
            training data. Deleting it clears them too and returns you to onboarding.
            """)
                .font(.caption)
                .foregroundStyle(Color.fbMuted)
        }
    }

    private var llmSection: some View {
        Section {
            ForEach(Array(viewModel.llmKeys.enumerated()), id: \.element.id) { index, entry in
                keyRow(
                    title: "\(index + 1). \(entry.provider.displayName)",
                    subtitle: entry.mask,
                    isMasked: true,
                    target: .llm(entry.provider),
                    canDelete: true
                )
            }
            .onMove { source, destination in
                Task { await viewModel.moveProviders(fromOffsets: source, toOffset: destination) }
            }
            if !viewModel.addableProviders.isEmpty {
                addProviderMenu
            }
        } header: {
            HStack {
                Text("AI PROVIDERS · PRIORITY ORDER")
                    .font(.fbLabel)
                    .foregroundStyle(Color.fbMuted)
                // Sits on the block it reorders rather than in the toolbar —
                // reordering is the only thing edit mode does on this screen,
                // and a toolbar button reads as applying to the whole page.
                // Reordering only means something with at least two providers.
                if viewModel.llmKeys.count > 1 {
                    Spacer()
                    EditButton()
                        .font(.fbLabel)
                        .foregroundStyle(Color.fbAccent)
                }
            }
            // Section headers uppercase their text; the label already is, and
            // "Edit"/"Done" must not be shouted.
            .textCase(nil)
        } footer: {
            Text(llmFooterText)
                .font(.caption)
                .foregroundStyle(Color.fbMuted)
        }
    }

    private var llmFooterText: String {
        guard !viewModel.llmKeys.isEmpty else {
            return "Without an AI provider key, the AI analysis stays unavailable."
        }
        return """
        The first provider is used for the analysis; the next one takes over when it fails or runs \
        out of credit. Tap Edit to drag them into a different order.
        """
    }

    private var addProviderMenu: some View {
        Menu {
            ForEach(viewModel.addableProviders) { provider in
                Button(provider.displayName) {
                    viewModel.beginEditing(.llm(provider))
                }
            }
        } label: {
            Label("Add a provider", systemImage: "plus")
                .font(.subheadline)
                .foregroundStyle(Color.fbAccent)
        }
        .listRowBackground(Color.fbCard)
    }

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInk)
            }
        } header: {
            Text("PRIVACY")
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
        }
        .listRowBackground(Color.fbCard)
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.isConfirmingDeleteAll = true
            } label: {
                HStack(spacing: 8) {
                    Label("Delete all data", systemImage: "trash")
                        .font(.subheadline)
                        .foregroundStyle(Color.fbRed)
                    if viewModel.isDeletingAll {
                        Spacer()
                        FBSpinner(size: 16, color: .fbMuted)
                    }
                }
            }
            .disabled(viewModel.isDeletingAll)
        } footer: {
            Text("""
            Removes every key, your consent, the cached training data and the provider order from \
            this device. Your Hevy and AI provider accounts themselves are not affected.
            """)
            .font(.caption)
            .foregroundStyle(Color.fbMuted)
        }
        .listRowBackground(Color.fbCard)
    }

    // MARK: - Rows

    /// Entry point to the Strava application credentials (#139). The
    /// connection itself — authorize, status, disconnect — comes with #140,
    /// which takes over this row.
    private var stravaRow: some View {
        NavigationLink {
            StravaCredentialsView(viewModel: makeStravaCredentialsViewModel())
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(StravaKeyPresentation.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.fbInk)
                Text("API application credentials")
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
            }
        }
        .listRowBackground(Color.fbCard)
    }

    /// One credential row: name, masked key, and an actions menu. The key is
    /// only ever shown masked (#83).
    private func keyRow(
        title: String,
        subtitle: String,
        isMasked: Bool,
        target: SettingsKeyTarget,
        canDelete: Bool
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.fbInk)
                Text(subtitle)
                    .font(.system(.footnote, design: isMasked ? .monospaced : .default))
                    .foregroundStyle(Color.fbInkSecondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button(canDelete ? "Replace key" : "Add key") {
                    viewModel.beginEditing(target)
                }
                if canDelete {
                    Button("Delete key", role: .destructive) {
                        viewModel.pendingDeletion = target
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.fbMuted)
            }
            .accessibilityLabel("\(target.displayName) key actions")
        }
        .listRowBackground(Color.fbCard)
    }

    // MARK: - Dialogs

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeletion != nil },
            set: { if !$0 { viewModel.pendingDeletion = nil } }
        )
    }

    private var deletionTitle: String {
        guard let target = viewModel.pendingDeletion else { return "Delete key?" }
        return "Delete the \(target.displayName) key?"
    }

    /// Every delete names its consequence (#83) — the Hevy key ends the
    /// session, the last LLM key ends AI analysis.
    private func deletionMessage(for target: SettingsKeyTarget) -> String {
        switch target {
        case .hevy:
            return """
            FitBuddy can no longer sync your workouts, the cached training data is deleted, and you \
            return to onboarding to enter a new key.
            """
        case .llm(let provider):
            if viewModel.llmKeys.count <= 1 {
                return """
                This is your last AI provider key. Without it the AI analysis stays unavailable \
                until you add a new one.
                """
            }
            return "\(provider.displayName) is removed from the fallback order. The remaining providers keep theirs."
        }
    }
}
