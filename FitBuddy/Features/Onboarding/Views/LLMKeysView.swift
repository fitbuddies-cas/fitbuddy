import SwiftUI

/// Onboarding step 3 (US-4): optionally add up to three LLM provider keys
/// (Claude, Gemini, Mistral). Each slot is a provider picker that reveals a
/// key field once a provider is chosen; the slot order is the fallback
/// priority for analysis calls. The keys are optional — a prominent "Skip"
/// CTA (AC2) sits alongside "Save & continue" and there is no live key
/// validation.
struct LLMKeysView: View {
    @ObservedObject var viewModel: LLMKeysViewModel

    private var isSaving: Bool { viewModel.state == .saving }

    private var failure: APIKeyEntryFailure? {
        if case .failed(let failure) = viewModel.state { return failure }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FBStepIndicator(current: 3)
                    .padding(.bottom, 22)
                Text("Connect an AI provider")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.fbInk)
                Text("Add up to three AI provider keys to unlock AI training analysis, or skip this for now — you can add them later.")
                    .font(.subheadline)
                    .foregroundStyle(Color.fbInkSecondary)
                    .padding(.top, 8)
                priorityNote
                    .padding(.top, 12)
                ForEach($viewModel.slots) { $slot in
                    slotSection($slot)
                        .padding(.top, 22)
                }
                if viewModel.slots.count < LLMKeysViewModel.maxSlots {
                    addSlotButton
                        .padding(.top, 18)
                }
                storageNote
                    .padding(.top, 14)
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
        // Only the structural changes — a slot added or removed, a provider
        // picked — not every keystroke: `slots` carries the key text, so
        // animating on the whole array restarts the transaction over the entire
        // subtree per typed character.
        .animation(.easeOut(duration: 0.15), value: viewModel.slots.map(\.provider))
    }

    // MARK: - Sections

    /// Explains that the slot order is the provider priority for the analysis
    /// call, including the fallback behavior (#79).
    private var priorityNote: some View {
        Label {
            Text("The order matters: the first provider is used for the analysis. If it fails or runs out of credit, the next one takes over automatically.")
                .font(.footnote)
                .foregroundStyle(Color.fbInkSecondary)
        } icon: {
            Image(systemName: "list.number")
                .font(.system(size: 14))
                .foregroundStyle(Color.fbMuted)
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

    /// One provider slot: picker first, then (once a provider is chosen) the
    /// where-to-find card and the key field.
    @ViewBuilder
    private func slotSection(_ slot: Binding<LLMKeySlot>) -> some View {
        let index = viewModel.slots.firstIndex(where: { $0.id == slot.wrappedValue.id }) ?? 0
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PROVIDER \(index + 1)")
                        .font(.fbLabel)
                        .foregroundStyle(Color.fbMuted)
                    Spacer()
                    if canRemove(slot.wrappedValue) {
                        removeSlotButton(for: slot.wrappedValue)
                    }
                }
                providerPicker(for: slot.wrappedValue)
            }
            if let provider = slot.wrappedValue.provider {
                whereToFindCard(for: provider)
                FBKeyField(
                    label: "\(provider.displayName.uppercased()) API KEY",
                    placeholder: provider.keyPlaceholder,
                    text: slot.key,
                    isBusy: isSaving,
                    hasError: failure == .keychain
                ) {
                    Task { await viewModel.save() }
                }
                if let note = provider.dataUsageNote {
                    dataUsageNote(note)
                }
            }
        }
    }

    /// A provider-specific warning about what it does with the data it
    /// receives — currently only Mistral's default-on training (ADR-007).
    /// Sits under the key field rather than in the picker: it matters at the
    /// moment the user commits to that provider, not while browsing.
    private func dataUsageNote(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.fbInkSecondary)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(Color.fbWarn)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fbWarnSoft)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
    }

    /// A slot can be cleared as soon as there is something to clear — a picked
    /// provider, or an extra slot beyond the first.
    private func canRemove(_ slot: LLMKeySlot) -> Bool {
        slot.provider != nil || viewModel.slots.count > 1
    }

    /// Undoes a provider choice: the picker itself only assigns, so this is the
    /// only way back out of a slot the user no longer wants.
    private func removeSlotButton(for slot: LLMKeySlot) -> some View {
        Button {
            viewModel.removeSlot(slot.id)
        } label: {
            Label("Remove", systemImage: "xmark.circle.fill")
                .font(.footnote)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.fbMuted)
        }
        .disabled(isSaving)
        .accessibilityLabel("Remove provider \(slot.provider?.displayName ?? "slot")")
    }

    /// Menu-backed dropdown listing only the providers not taken by another
    /// slot.
    private func providerPicker(for slot: LLMKeySlot) -> some View {
        Menu {
            ForEach(viewModel.availableProviders(for: slot)) { provider in
                Button(provider.displayName) {
                    viewModel.select(provider, forSlot: slot.id)
                }
            }
        } label: {
            HStack {
                Text(slot.provider?.displayName ?? "Choose a provider")
                    .font(.subheadline)
                    .foregroundStyle(slot.provider == nil ? Color.fbMuted : Color.fbInk)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fbMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(Color.fbCard)
            .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
            .overlay(
                RoundedRectangle(cornerRadius: FBRadius.control)
                    .strokeBorder(Color.fbBorder, lineWidth: 1)
            )
        }
        .disabled(isSaving)
    }

    /// Explains where the key lives in the provider's console.
    private func whereToFindCard(for provider: LLMProvider) -> some View {
        HStack(alignment: .top, spacing: 12) {
            screenshotPlaceholder
            VStack(alignment: .leading, spacing: 6) {
                Text(.markdownOrPlain(provider.consoleInstructions))
                    .font(.footnote)
                    .foregroundStyle(Color.fbInkSecondary)
                Link(destination: provider.consoleURL) {
                    Text("Open \(provider.consoleName) ↗")
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

    private var addSlotButton: some View {
        Button {
            viewModel.addSlot()
        } label: {
            Label("Add next API key", systemImage: "plus")
        }
        .buttonStyle(.fb(.secondary))
        .disabled(!viewModel.canAddSlot)
    }

    private var storageNote: some View {
        Label("Stored in Apple Keychain · this device only · optional", systemImage: "lock")
            .font(.caption)
            .foregroundStyle(Color.fbMuted)
            .padding(.leading, 2)
    }

    /// Copy comes from `APIKeyEntryFailure`, like on the other two key
    /// screens: this step can only fail on the Keychain, and that banner must
    /// not drift from the one settings and step 2 show for the same problem.
    /// No provider is named — the step saves up to three keys at once.
    private func errorBanner(for failure: APIKeyEntryFailure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(failure.title())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbRed)
            Text(failure.message())
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

    /// Save (primary) and Skip (prominent secondary, AC2) stacked.
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
                Task { await viewModel.skip() }
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
    LLMKeysView(viewModel: LLMKeysViewModel())
}
