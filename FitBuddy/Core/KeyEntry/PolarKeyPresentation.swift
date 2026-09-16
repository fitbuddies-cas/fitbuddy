import Foundation

/// Everything the Polar screens need to talk about the user's API application
/// (ADR-11 Nachtrag): the provider name, placeholders for the two credentials,
/// and where the user creates them. Counterpart of `StravaKeyPresentation` —
/// Polar is a single fixed provider too, so this is a namespace rather than an
/// instance.
///
/// Named after the *presentation*: the stored secrets are
/// `KeychainKey.polarClientID` and `.polarClientSecret`.
enum PolarKeyPresentation {
    /// User-facing provider name.
    static let displayName = "Polar"

    /// Placeholder hinting at the UUID-shaped client ID.
    static let clientIDPlaceholder = "a1b2c3d4-e5f6-…"

    /// Placeholder hinting at the hex secret.
    static let clientSecretPlaceholder = "a1b2c3d4…"

    /// Host name of the page that manages the application, for link labels.
    static let consoleName = "admin.polaraccesslink.com"

    /// Polar page where the user registers and manages their AccessLink
    /// application.
    static let consoleURL = URL(staticString: "https://admin.polaraccesslink.com")

    /// The value the user has to enter as the application's "Authorization
    /// redirect URL" — FitBuddy's fixed URL scheme (`PolarClientConfiguration`).
    static let redirectURI = PolarClientConfiguration.redirectURI

    /// Where-to-find instructions shown on the credentials card (markdown).
    static let consoleInstructions = """
        FitBuddy uses your own Polar AccessLink application, so no key of ours is involved. \
        Register one at **admin.polaraccesslink.com**, set the **Authorization redirect URL** to \
        **`\(redirectURI)`**, then copy the **Client ID** and **Client Secret** shown there.
        """
}
