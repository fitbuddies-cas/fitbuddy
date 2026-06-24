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
                        title: "Data transfer to Anthropic (USA)",
                        text: """
                        Your training data is health data (Art. 5 lit. c nDSG). For the AI \
                        analysis it is transferred to Anthropic. Your contracting party is \
                        Anthropic Ireland, Limited (Irish law); the technical processing takes \
                        place in the USA by Anthropic PBC. The USA does not provide a level of \
                        data protection equivalent to Swiss law. The transfer is based on the \
                        Anthropic DPA of your own account (incl. SCCs + Swiss Addendum).
                        """
                    )
                    disclosure(
                        icon: "cross.case",
                        title: "Not a medical device",
                        text: """
                        FitBuddy is not a medical product and does not replace medical or \
                        therapeutic advice. You are responsible for any recommendations you \
                        choose to act on.
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
            .navigationTitle("Before we start")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        Text("For FitBuddy to support your training, we need your consent to the following data processing.")
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
            Label("Read privacy policy", systemImage: "doc.text")
        }
    }

    private var consentToggle: some View {
        Toggle(isOn: $viewModel.hasAcceptedCheckbox) {
            Text("I have read the information above and consent to the described data processing.")
                .font(.subheadline)
        }
    }

    private var confirmButton: some View {
        Button {
            Task { await viewModel.confirm() }
        } label: {
            Text("Confirm and continue")
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
