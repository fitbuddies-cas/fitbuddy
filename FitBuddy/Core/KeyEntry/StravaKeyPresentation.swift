import Foundation

/// Everything the Strava screens need to talk about the user's API application
/// (ADR-10): the provider name, placeholders for the two credentials, and where
/// the user creates them. Counterpart of `HevyKeyPresentation` — Strava is a
/// single fixed provider too, so this is a namespace rather than an instance.
///
/// Named after the *presentation*: the stored secrets are
/// `KeychainKey.stravaClientID` and `.stravaClientSecret`.
enum StravaKeyPresentation {
    /// User-facing provider name.
    static let displayName = "Strava"

    /// Placeholder hinting at the numeric client ID.
    static let clientIDPlaceholder = "123456"

    /// Placeholder hinting at the 40-character hex secret.
    static let clientSecretPlaceholder = "a1b2c3d4…"

    /// Host name of the page that manages the application, for link labels.
    static let consoleName = "strava.com"

    /// Strava page where the user creates and manages their API application.
    static let consoleURL = URL(staticString: "https://www.strava.com/settings/api")

    /// The value the user has to enter as "Authorization Callback Domain" in
    /// that application. Strava matches it against the *host* of the redirect
    /// URI (`fitbuddy://localhost/strava`, see `StravaOAuthService`), not the
    /// scheme — anything else is rejected as "invalid redirect_uri".
    static let callbackDomain = "localhost"

    /// Where-to-find instructions shown on the credentials card (markdown).
    /// The full walkthrough is `StravaSetupGuideView` (#168), linked from the
    /// same card — the repository is private, so no link to the docs.
    static let consoleInstructions = """
        FitBuddy uses your own Strava API application, so no key of ours is involved. \
        Log in at **strava.com**, open **Settings → My API Application**, and create one. \
        Set the **Authorization Callback Domain** to **`\(callbackDomain)`**, then copy the \
        **Client ID** and **Client Secret** shown there.
        """
}
