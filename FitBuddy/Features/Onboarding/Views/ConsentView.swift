import SwiftUI

/// Consent screen shown before any app access (US-4 / AC4). Presents the three
/// mandatory disclosures, a link to the privacy policy, and a confirm button
/// that stays disabled until the user ticks the checkbox. Styled with the
/// shared design system (`Core/DesignSystem`).
struct ConsentView: View {
    @ObservedObject var viewModel: ConsentViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    FBCard {
                        VStack(alignment: .leading, spacing: 20) {
                            FBInfoRow(
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
                            Divider().overlay(Color.fbDivider)
                            FBInfoRow(
                                icon: "cross.case",
                                title: "Not a medical device",
                                text: """
                                FitBuddy is not a medical product and does not replace medical or \
                                therapeutic advice. You are responsible for any recommendations you \
                                choose to act on.
                                """
                            )
                        }
                    }
                    privacyLink
                    consentToggle
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.fbRed)
                    }
                    confirmButton
                }
                .padding()
            }
            .background(Color.fbBackground)
            .navigationTitle("Before we start")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        Text("For FitBuddy to support your training, we need your consent to the following data processing.")
            .font(.subheadline)
            .foregroundStyle(Color.fbInkSecondary)
    }

    private var privacyLink: some View {
        NavigationLink {
            PrivacyPolicyView()
        } label: {
            Label("Read privacy policy", systemImage: "doc.text")
                .font(.subheadline)
                .foregroundStyle(Color.fbAccent)
        }
    }

    private var consentToggle: some View {
        Toggle(isOn: $viewModel.hasAcceptedCheckbox) {
            Text("I have read the information above and consent to the described data processing.")
                .font(.subheadline)
                .foregroundStyle(Color.fbInk)
        }
        .tint(.fbAccent)
    }

    private var confirmButton: some View {
        Button {
            Task { await viewModel.confirm() }
        } label: {
            Text("Confirm and continue")
        }
        .buttonStyle(.fb(.primary))
        .disabled(!viewModel.canConfirm)
    }
}

#Preview {
    ConsentView(viewModel: ConsentViewModel())
}
