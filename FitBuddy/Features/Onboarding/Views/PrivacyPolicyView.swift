import SwiftUI

/// Static privacy policy reachable from the consent screen (and later from
/// Settings). Content follows the mandatory items required by the project's
/// non-functional requirements: controller, processed data, purpose, third
/// parties, third country, and data-subject rights.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro
                section(
                    title: "Controller",
                    text: """
                    The party responsible for the data processing is the FitBuddy project \
                    team (CAS study project, BFH Biel). FitBuddy is distributed solely via \
                    TestFlight to test users as part of a proof of concept.
                    """
                )
                section(
                    title: "What data we process",
                    text: """
                    • Training data from your Hevy account (workouts, exercises, sets) — \
                    this qualifies as health data under Art. 5 lit. c nDSG.
                    • Your Hevy and Claude API keys.
                    • The time and version of your consent.
                    """
                )
                section(
                    title: "Purpose",
                    text: """
                    The data is used solely to show you an AI-assisted analysis and training \
                    recommendations on request. There is no tracking, no advertising, and no \
                    evaluation across multiple users.
                    """
                )
                section(
                    title: "Recipients (third parties)",
                    text: """
                    • Hevy: source of your training data, fetched directly from your device \
                    with your own API key.
                    • Anthropic: recipient of the training data for the AI analysis, called \
                    directly from your device with your own API key.
                    No data is transferred to any other third parties or to servers operated \
                    by the FitBuddy team.
                    """
                )
                section(
                    title: "Third country USA",
                    text: """
                    The AI analysis is performed by Anthropic. Your contracting party is \
                    Anthropic Ireland, Limited; the technical processing takes place in the \
                    USA by Anthropic PBC. There is no adequacy decision for the USA; the level \
                    of data protection is not equivalent to Swiss law. The transfer is based \
                    on the Anthropic DPA of your own account (incl. Standard Contractual \
                    Clauses and Swiss Addendum), which applies automatically once you create \
                    your Anthropic account.
                    """
                )
                section(
                    title: "Local storage",
                    text: """
                    API keys and consent data are stored exclusively in your device's iOS \
                    Keychain (this device only, no iCloud sync). They only leave your device \
                    during your own API calls to Hevy or Anthropic.
                    """
                )
                section(
                    title: "Your rights",
                    text: """
                    You have the right to access the processed data and to have it deleted. \
                    You can remove all locally stored data (API keys, cache, consent) at any \
                    time via “Delete data / reset account” in Settings; the app then returns \
                    to the onboarding state.
                    """
                )
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        Text("This statement describes which data FitBuddy processes and why.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func section(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
