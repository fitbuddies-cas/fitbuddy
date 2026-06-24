import SwiftUI

/// Consent screen shown before any app access (US-4 / AC4). Presents the three
/// mandatory disclosures, a link to the privacy policy, and a confirm button
/// that stays disabled until the user ticks the checkbox.
struct ConsentView: View {
    @ObservedObject var viewModel: ConsentViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    disclosure(
                        icon: "globe",
                        title: "Datenübertragung an Anthropic (USA)",
                        text: """
                        Deine Trainingsdaten sind Gesundheitsdaten (Art. 5 lit. c nDSG). \
                        Für die KI-Analyse werden sie an Anthropic übertragen. Vertragspartner \
                        ist Anthropic Ireland, Limited (irisches Recht); die technische \
                        Verarbeitung erfolgt in den USA durch Anthropic PBC. Die USA bieten \
                        kein dem Schweizer Recht gleichwertiges Datenschutzniveau. Grundlage \
                        der Übertragung ist der Anthropic-DPA deines eigenen Accounts \
                        (inkl. SCCs + Swiss Addendum).
                        """
                    )
                    disclosure(
                        icon: "cross.case",
                        title: "Kein Medizinprodukt",
                        text: """
                        FitBuddy ist kein medizinisches Produkt und ersetzt keine ärztliche \
                        oder therapeutische Beratung. Du trägst selbst die Verantwortung für \
                        umgesetzte Empfehlungen.
                        """
                    )
                    privacyLink
                    consentToggle
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    confirmButton
                }
                .padding()
            }
            .navigationTitle("Bevor es losgeht")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        Text("Damit FitBuddy dich beim Training unterstützen kann, brauchen wir deine Einwilligung in die folgende Datenbearbeitung.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func disclosure(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var privacyLink: some View {
        NavigationLink {
            PrivacyPolicyView()
        } label: {
            Label("Datenschutzerklärung lesen", systemImage: "doc.text")
        }
    }

    private var consentToggle: some View {
        Toggle(isOn: $viewModel.hasAcceptedCheckbox) {
            Text("Ich habe die Hinweise gelesen und willige in die beschriebene Datenbearbeitung ein.")
                .font(.subheadline)
        }
    }

    private var confirmButton: some View {
        Button {
            Task { await viewModel.confirm() }
        } label: {
            Text("Bestätigen und fortfahren")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!viewModel.canConfirm)
    }
}

#Preview {
    ConsentView(viewModel: ConsentViewModel())
}
