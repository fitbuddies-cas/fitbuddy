import Foundation

/// Fixed, non-secret facts about the Polar AccessLink **v3** API that hold for
/// every user (ADR-11 Nachtrag): the OAuth and REST endpoints, and the
/// redirect URI registered in `Info.plist`. The user-specific half —
/// `PolarClientCredentials` (clientID/clientSecret) — is entered on the
/// credentials screen (#139-style, BYO-app) and stored in their own Keychain.
///
/// **These hosts are v3-specific and not interchangeable with v4** (Nachtrag,
/// found while debugging the first real end-to-end connect attempt): a client
/// registered at `admin.polaraccesslink.com` (v3) only authenticates against
/// `flow.polar.com`/`polarremote.com`. The unrelated v4 API
/// (`polar.com/polar-api-v4`) has its own host, `auth.polar.com` — pointing a
/// v3 client at it fails with an opaque redirect/response the app cannot
/// explain, which is exactly what `auth.polar.com` was doing here before this
/// fix. `PolarConnector` targets the v3 `exercises` resource, so OAuth has to
/// stay v3 too.
enum PolarClientConfiguration {
    /// Registered redirect URI. Every user's own Polar application has to
    /// list this same value — it is FitBuddy's URL scheme, not a per-user
    /// setting.
    static let redirectURI = "fitbuddy://polar/callback"

    /// Read access to all training sessions. Optional per the v3 docs
    /// (omitting it grants every scope) but sent explicitly so a future scope
    /// split does not silently over-grant.
    static let scope = "accesslink.read_all"

    /// OAuth2 authorization endpoint (AccessLink v3). Does not support PKCE —
    /// see `PolarOAuthClient`.
    static let authorizationURL = URL(staticString: "https://flow.polar.com/oauth2/authorization")

    /// OAuth2 token endpoint (AccessLink v3): code exchange + refresh.
    static let tokenURL = URL(staticString: "https://polarremote.com/v2/oauth2/token")

    /// AccessLink REST base. `PolarConnector` targets the v3 `exercises`
    /// resource, whose response schema is stable and documented; migrating to
    /// the v4 `training-sessions` resource is tracked as an open point in
    /// ADR-11.
    static let accessLinkBaseURL = URL(staticString: "https://www.polaraccesslink.com/v3")
}
