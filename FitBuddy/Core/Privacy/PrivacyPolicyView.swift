import SwiftUI

/// Static privacy policy reachable from the consent screen (US-4) and from
/// Settings (#83). Content follows the mandatory items required by the project's
/// non-functional requirements: controller, processed data, purpose, third
/// parties, third country, and data-subject rights. Styled with the shared
/// design system (`Core/DesignSystem`).
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                FBCard {
                    VStack(alignment: .leading, spacing: 20) {
                        FBInfoRow(
                            title: "Controller",
                            text: """
                            The party responsible for the data processing is the FitBuddy project \
                            team (CAS study project, BFH Biel). FitBuddy is distributed solely via \
                            TestFlight to test users as part of a proof of concept.
                            """
                        )
                        Divider().overlay(Color.fbDivider)
                        FBInfoRow(
                            title: "What data we process",
                            text: """
                            • Training data from your Hevy account (workouts, exercises, sets) \
                            and, if you connect it, your Strava account (activities with \
                            distance and duration) — this qualifies as health data under \
                            Art. 5 lit. c nDSG.
                            • Your Hevy API key, the API keys of the AI providers you connect \
                            (Claude, Gemini, and/or Mistral), and — for Strava — the client ID \
                            and client secret of your own Strava API application together with \
                            the access and refresh tokens Strava issues for it.
                            • The time and version of your consent.
                            """
                        )
                        Divider().overlay(Color.fbDivider)
                        FBInfoRow(
                            title: "Purpose",
                            text: """
                            The data is used solely to show you an AI-assisted analysis and training \
                            recommendations on request. There is no tracking, no advertising, and no \
                            evaluation across multiple users.
                            """
                        )
                        Divider().overlay(Color.fbDivider)
                        FBInfoRow(
                            title: "Recipients (third parties)",
                            text: """
                            • Hevy: source of your training data, fetched directly from your device \
                            with your own API key.
                            • Strava, Inc. (USA), if you connect it: source of your activities, \
                            fetched directly from your device through an API application that \
                            you register in your own Strava account. Strava receives your \
                            authorization and the read requests; it never receives your Hevy \
                            data or the AI analysis.
                            • AI providers — Anthropic (Claude), Google (Gemini), Mistral AI: \
                            recipients of the training data for the AI analysis, called directly \
                            from your device with your own API keys. Only the providers you have \
                            added a key for receive any data, in the priority order you chose.
                            No data is transferred to any other third parties or to servers operated \
                            by the FitBuddy team.
                            """
                        )
                        Divider().overlay(Color.fbDivider)
                        FBInfoRow(
                            title: "Third country USA",
                            text: """
                            The AI analysis is performed by the providers you connect. Anthropic \
                            (your contracting party is Anthropic Ireland, Limited; the technical \
                            processing takes place in the USA by Anthropic PBC) and Google process \
                            data in the USA. There is no adequacy decision for the USA; the level \
                            of data protection is not equivalent to Swiss law. Each transfer is \
                            based on the API terms of your own account with that provider — for \
                            Anthropic, the DPA (incl. Standard Contractual Clauses and Swiss \
                            Addendum), which applies automatically once you create your account. \
                            Mistral AI processes data within the EU. Strava, Inc. likewise \
                            processes data in the USA, under the API agreement of your own \
                            Strava account.
                            """
                        )
                        Divider().overlay(Color.fbDivider)
                        FBInfoRow(
                            title: "Local storage",
                            text: """
                            API keys, the Strava application credentials and tokens, and consent \
                            data are stored exclusively in your device's iOS Keychain (this device \
                            only, no iCloud sync). They only leave your device during your own API \
                            calls to Hevy, Strava or your AI providers. Disconnecting Strava in \
                            Settings removes every Strava item from the Keychain and every Strava \
                            activity from the local cache.
                            """
                        )
                        Divider().overlay(Color.fbDivider)
                        FBInfoRow(
                            title: "Your rights",
                            text: """
                            You have the right to access the processed data and to have it deleted. \
                            You can remove all locally stored data (API keys, cache, consent) at any \
                            time via “Delete data / reset account” in Settings; the app then returns \
                            to the onboarding state.
                            """
                        )
                    }
                }
            }
            .padding()
        }
        .background(Color.fbBackground)
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        Text("This statement describes which data FitBuddy processes and why.")
            .font(.subheadline)
            .foregroundStyle(Color.fbInkSecondary)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
