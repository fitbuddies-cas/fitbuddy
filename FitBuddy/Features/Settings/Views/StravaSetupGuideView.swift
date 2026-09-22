import SwiftUI

/// In-app version of the Strava setup guide (#168): how to create the user's
/// own Strava API application, why the callback domain is `localhost`, and
/// what each failure banner means. Reachable from the connection screen (#140)
/// and the credentials screen (#139).
///
/// The repository is private, so a link to `docs/STRAVA-SETUP.md` is a dead
/// end for testers — the content lives here instead. Static like
/// `PrivacyPolicyView`: no view model, styled with `Core/DesignSystem`.
struct StravaSetupGuideView: View {
    private static let appsURL = URL(staticString: "https://www.strava.com/settings/apps")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                whySection
                requirementsSection
                stepOne
                stepTwo
                stepThree
                stepFour
                stepFive
                approvalSection
                tokenSection
                troubleshootingSection
                resetSection
                privacySection
            }
            .padding()
        }
        .background(Color.fbBackground)
        .navigationTitle("Strava setup guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Creating your own Strava API application takes about five minutes. There is exactly one pitfall: the Authorization Callback Domain must be `localhost`. Everything else is filling in required fields.")
                .font(.subheadline)
                .foregroundStyle(Color.fbInkSecondary)
            Text("Checked against the Strava form in September 2026. If Strava renames a field, use the one with the closest name.")
                .font(.caption)
                .foregroundStyle(Color.fbMuted)
        }
    }

    // MARK: - Sections

    private var whySection: some View {
        FBCard {
            FBInfoRow(
                icon: "person.badge.key",
                title: "Why you need your own application",
                text: """
                FitBuddy has no backend and ships no Strava integration of its own. Instead, \
                the connection runs through a Strava API application that belongs to you — \
                just like your Hevy API key and your AI key. You create it once on strava.com \
                and enter its client ID and client secret in FitBuddy. Then you authorize \
                FitBuddy in a Strava sign-in sheet, and the app reads your activities.
                """
            )
        }
    }

    private var requirementsSection: some View {
        FBCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("What you need", icon: "checklist")
                bullet("A Strava account with an **active Strava subscription**. Strava names the subscription as a prerequisite for creating an API application. With a free account you cannot create one — and therefore cannot connect FitBuddy.")
                bullet("A browser, ideally on a Mac or PC — the form is cramped on a phone.")
                bullet("FitBuddy on your iPhone with onboarding completed (Hevy key and AI key stored).")
                bullet("Any square image as the app icon (PNG or JPG). Strava requires one; the content does not matter.")
            }
        }
    }

    private var stepOne: some View {
        stepCard(number: 1, title: "Open the Strava settings") {
            numbered(1, "Sign in to strava.com in your browser.")
            numbered(2, "Open **Settings → My API Application**, or the link below.")
            numbered(3, "If you have no application yet, Strava shows the «Create an App» form. If you already have one, you see its data — you can reuse it for FitBuddy as long as the callback domain is right (step 3).")
            consoleLink
            note("Strava allows **one** API application per account. If you already use it for another tool, you can still use it for FitBuddy: client ID and secret stay the same, only the callback domain has to suit both tools. With `localhost` that is usually the case.")
        }
    }

    private var stepTwo: some View {
        stepCard(number: 2, title: "Create the application") {
            Text("Fill in the form as follows. All fields are required unless marked optional.")
                .font(.subheadline)
                .foregroundStyle(Color.fbInkSecondary)
            field("Application Name", value: "FitBuddy", note: "Must not contain «Strava». Appears in the consent sheet and under «My Apps».")
            field("Category", value: "Training or Data Importer", note: "Administrative only, no effect on the connection.")
            field("Club", value: "leave empty", note: "Optional. Only relevant for club integrations.")
            field("Website", value: "https://github.com/fitbuddies-cas/fitbuddy", note: "Required but not verified. Any valid https:// URL works.")
            field("Application Description", value: "Private FitBuddy connection, my own account only", note: "Free text, at least a few words.")
            field("Authorization Callback Domain", value: StravaKeyPresentation.callbackDomain, note: "Exactly like this, lowercase, without http://, without path, without port. See step 3.", highlighted: true)
            Text("Tick «I have read and agree to the API Agreement» and tap **Create**.")
                .font(.subheadline)
                .foregroundStyle(Color.fbInkSecondary)
            Text("After creating, Strava asks for an **app icon** («Upload an icon»). Upload the square image you prepared. Only then does Strava show the full application data including the client secret.")
                .font(.subheadline)
                .foregroundStyle(Color.fbInkSecondary)
        }
    }

    private var stepThree: some View {
        stepCard(number: 3, title: "Authorization Callback Domain: localhost") {
            Text("This value decides whether the connection works.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbInk)
            paragraph("**Why `localhost`?** After you authorize, Strava sends the browser back to `fitbuddy://localhost/strava`, where FitBuddy picks up the answer. Strava does not check the scheme (`fitbuddy://`), only the **host** of that address — and that is `localhost`. Strava explicitly lists `localhost` as a valid value for apps without a web domain; FitBuddy needs no website and no backend.")
            paragraph("**What happens with another value?** Anything else — `fitbuddy`, `fitbuddy.app`, `www.strava.com`, `localhost/strava`, `http://localhost`, or a stray space — makes Strava abort the sign-in before the consent page even appears. The sheet then shows **«invalid redirect_uri»**, or FitBuddy reports «Strava did not send FitBuddy back correctly».")
            paragraph("You can change the callback domain on strava.com at any time and simply tap **Connect** again in FitBuddy. The stored client credentials stay valid.")
        }
    }

    private var stepFour: some View {
        stepCard(number: 4, title: "Enter client ID and client secret in FitBuddy") {
            numbered(1, "On strava.com, «My API Application» now shows **Client ID** (a number, e.g. `123456`) and **Client Secret** (tap **Show**; a 40-character hex string).")
            numbered(2, "In FitBuddy, open **Settings → Strava**.")
            numbered(3, "Tap **Enter API application credentials**.")
            numbered(4, "Enter **CLIENT ID** and **CLIENT SECRET**. Easiest is copying both values via the iCloud clipboard from your Mac to your iPhone; if you type them, check every character of the secret.")
            numbered(5, "Tap **Save credentials**. FitBuddy stores both values in your iPhone's Keychain and returns to the Strava screen.")
            note("The client secret is never shown in plain text again, only masked («Stored application»). To replace it later, tap **API application credentials** again and save a new pair.")
        }
    }

    private var stepFive: some View {
        stepCard(number: 5, title: "Connect and confirm access") {
            numbered(1, "Tap **Connect with Strava**. A Strava sign-in sheet opens.")
            numbered(2, "Sign in if needed.")
            numbered(3, "Strava shows the consent page of your application. Keep **«View data about your private activities»** ticked — that is the `activity:read_all` permission FitBuddy needs to read activities set to «Only You» on Strava. Without it FitBuddy reports «Activity access was not granted» and you have to reconnect.")
            numbered(4, "Tap **Authorize**. The sheet closes and FitBuddy shows **Connected** with the validity of the current access token.")
            numbered(5, "Back on the dashboard: on the next sync your Strava activities of the last 90 days appear next to your Hevy workouts, marked with Strava as the source.")
            note("FitBuddy only asks for read access to activities. It reads no profile data and never writes anything back to Strava.")
        }
    }

    private var approvalSection: some View {
        FBCard {
            FBInfoRow(
                icon: "person.crop.circle.badge.checkmark",
                title: "Do I need Strava to approve the application?",
                text: """
                No. Every new Strava application starts in «single-player mode»: only the \
                Strava account that created it can authorize it. That is exactly right for \
                FitBuddy, because your application connects your own account only. Do not \
                request approval for more users — that review process is for public apps \
                and of no use to you.

                Rate limits apply per application: 200 requests per 15 minutes, 2,000 per \
                day. A FitBuddy sync uses a handful of them; nobody but you shares this quota.
                """
            )
        }
    }

    private var tokenSection: some View {
        FBCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("What happens next", icon: "arrow.triangle.2.circlepath")
                bullet("The **access token** is valid for six hours. FitBuddy renews it automatically during sync via the refresh token — you will not notice.")
                bullet("Strava issues a **new refresh token** on every renewal; FitBuddy stores it.")
                bullet("Only when the refresh token itself stops working («Renew your Strava connection» below) do you have to reconnect once.")
            }
        }
    }

    private var troubleshootingSection: some View {
        FBCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Troubleshooting", icon: "wrench.and.screwdriver")
                trouble(
                    "«invalid redirect_uri» in the Strava sheet, or «Strava did not send FitBuddy back correctly» in FitBuddy",
                    cause: "The Authorization Callback Domain of your application is not `localhost`.",
                    fix: "Set the callback domain to `localhost` on strava.com (step 3), then tap **Try again** in FitBuddy."
                )
                Divider().overlay(Color.fbDivider)
                trouble(
                    "«Strava rejected the application credentials»",
                    cause: "Client ID or client secret match no application: a typo, a missing character, or you regenerated the secret on strava.com.",
                    fix: "Tap **Show** next to the client secret on strava.com and compare both values. In FitBuddy tap **Check the application credentials →**, save the pair again, then reconnect."
                )
                Divider().overlay(Color.fbDivider)
                trouble(
                    "«Activity access was not granted»",
                    cause: "«View data about your private activities» was unticked when authorizing.",
                    fix: "Tap **Try again** and leave the box ticked this time."
                )
                Divider().overlay(Color.fbDivider)
                trouble(
                    "«Strava access was declined»",
                    cause: "You chose **Cancel** on the consent page.",
                    fix: "Nothing was stored. Tap **Connect with Strava** again."
                )
                Divider().overlay(Color.fbDivider)
                trouble(
                    "Dashboard says «Renew your Strava connection», Strava screen shows «Connection expired»",
                    cause: "The refresh token is invalid: you revoked FitBuddy on strava.com under **Settings → My Apps**, regenerated the client secret, or Strava blocked the token.",
                    fix: "Tap the dashboard notice (it opens the Strava screen) and tap **Reconnect**. If you regenerated the secret, save the new secret first."
                )
                Divider().overlay(Color.fbDivider)
                trouble(
                    "«Could not reach Strava»",
                    cause: "No internet, DNS or timeout problem.",
                    fix: "Check your connection, then **Try again**."
                )
                Divider().overlay(Color.fbDivider)
                trouble(
                    "«Strava is currently unavailable»",
                    cause: "Strava answered with an unexpected error; nothing was rejected.",
                    fix: "**Try again** a little later."
                )
                Divider().overlay(Color.fbDivider)
                trouble(
                    "«Could not update the Strava connection»",
                    cause: "Your iPhone's Keychain refused access.",
                    fix: "Unlock the iPhone and try again."
                )
                Divider().overlay(Color.fbDivider)
                trouble(
                    "The sign-in sheet stays blank or hangs",
                    cause: "The Strava page does not load, usually a network issue.",
                    fix: "Close the sheet (counts as cancel, nothing is stored) and connect again."
                )
            }
        }
    }

    private var resetSection: some View {
        FBCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Disconnect and start over", icon: "arrow.counterclockwise")
                paragraph("On **Settings → Strava**, **Disconnect** removes the connection. FitBuddy deletes the access and refresh tokens, the stored client ID and secret, **and** every cached Strava activity from the dashboard. The application on strava.com stays; to set up again, enter the pair once more (step 4) and connect (step 5).")
                paragraph("To revoke FitBuddy on Strava's side as well, use «Revoke Access» on the page below. FitBuddy then reports «Renew your Strava connection» on the next sync.")
                Link(destination: Self.appsURL) {
                    Text("Open strava.com/settings/apps ↗")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.fbAccent)
                }
                paragraph("**Settings → Delete all data** also removes every Strava item from the device.")
            }
        }
    }

    private var privacySection: some View {
        FBCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Privacy", icon: "lock")
                bullet("**Client secret and tokens never leave your iPhone.** They sit in the iOS Keychain (this device only, when unlocked), are not backed up to iCloud, and are used only for your own requests to strava.com. No server of the FitBuddy team is involved.")
                bullet("**Strava as a data recipient** is listed in the app's privacy policy and consent text: Strava, Inc. (USA) is the source of your activities; FitBuddy sends Strava only the authorization request of your own application. Your activities do not flow into the AI analysis in this version.")
                bullet("**You remain Strava's contracting party.** By creating the application you accept Strava's API Agreement yourself; the FitBuddy team has no access to your application or your data.")
                bullet("**Deleting:** «Disconnect» or «Delete all data» removes everything Strava-related from the device; «Revoke Access» on strava.com ends the permission on Strava's side.")
            }
        }
    }

    // MARK: - Building blocks

    private var consoleLink: some View {
        Link(destination: StravaKeyPresentation.consoleURL) {
            Text("Open \(StravaKeyPresentation.consoleName)/settings/api ↗")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.fbAccent)
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.fbAccent)
                .frame(width: 28)
            Text(title)
                .font(.fbTitle)
                .foregroundStyle(Color.fbInk)
        }
    }

    private func stepCard<Content: View>(
        number: Int,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        FBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(number)")
                        .font(.fbLabel)
                        .foregroundStyle(Color.fbAccentInk)
                        .frame(width: 24, height: 24)
                        .background(Color.fbAccentSoft)
                        .clipShape(Circle())
                    Text(title)
                        .font(.fbTitle)
                        .foregroundStyle(Color.fbInk)
                }
                content()
            }
        }
    }

    private func paragraph(_ markdown: String) -> some View {
        Text(.markdownOrPlain(markdown))
            .font(.subheadline)
            .foregroundStyle(Color.fbInkSecondary)
    }

    private func bullet(_ markdown: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .font(.subheadline)
                .foregroundStyle(Color.fbMuted)
            paragraph(markdown)
        }
    }

    private func numbered(_ number: Int, _ markdown: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbInk)
                .fbTabularNumbers()
            paragraph(markdown)
        }
    }

    private func note(_ markdown: String) -> some View {
        paragraph(markdown)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fbCardSubtle)
            .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
    }

    /// One row of the Strava form: field name, what to enter, and a hint.
    /// The callback domain is the one that breaks the connection when wrong,
    /// so it gets the warn tint.
    private func field(_ name: String, value: String, note: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(highlighted ? .semibold : .regular))
                .foregroundStyle(Color.fbInk)
            Text(note)
                .font(.footnote)
                .foregroundStyle(Color.fbInkSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Color.fbWarnSoft : Color.fbCardSubtle)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.control))
        .overlay(
            RoundedRectangle(cornerRadius: FBRadius.control)
                .strokeBorder(highlighted ? Color.fbWarn : Color.fbBorder, lineWidth: 1)
        )
    }

    private func trouble(_ symptom: String, cause: String, fix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(symptom)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.fbInk)
            labelled("Cause", cause)
            labelled("Fix", fix)
        }
    }

    private func labelled(_ label: String, _ markdown: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.fbLabel)
                .foregroundStyle(Color.fbMuted)
                .textCase(.uppercase)
                .frame(width: 44, alignment: .leading)
            paragraph(markdown)
        }
    }
}

#Preview {
    NavigationStack {
        StravaSetupGuideView()
    }
}
