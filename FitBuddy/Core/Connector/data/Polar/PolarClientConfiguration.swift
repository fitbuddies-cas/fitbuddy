import Foundation

/// Everything a `PolarConnector` needs that is fixed per FitBuddy build
/// rather than per user (ADR-11).
///
/// The `clientID` / `redirectURI` come from the OAuth client registered at
/// <https://admin.polaraccesslink.com>. There is no bundled default: a real
/// value is a partner credential the team registers, and shipping a
/// placeholder that silently produces `invalid_client` at runtime would be
/// worse than a missing-configuration error at start-up.
///
/// **`clientSecret` is not optional in practice (Nachtrag zu ADR-11).** The
/// original decision assumed a PKCE-only public client, no secret required —
/// Polar's AccessLink docs (both v3 `polarremote.com` and the v4
/// `auth.polar.com` this type targets) say otherwise: every token exchange
/// authenticates with HTTP Basic `clientID:clientSecret`, PKCE or not. The
/// field stays `String?` because `PolarOAuthClient` degrades to a public-client
/// request when it is `nil` (useful for the parts of the test suite that never
/// reach a real token endpoint), but a build without it cannot actually
/// connect. This is demo-only wiring for the CAS presentation: the secret is a
/// team credential with no backend to hide it behind, so it never belongs in
/// a build distributed beyond the presenter's own device (see the ADR-11
/// Nachtrag for the v1 options — a backend, or a Strava-style BYO-app screen).
struct PolarClientConfiguration: Sendable {
    let clientID: String
    /// Registered redirect URI, e.g. a custom scheme `fitbuddy://polar-oauth`.
    let redirectURI: String
    let clientSecret: String?

    /// OAuth2 authorization endpoint. Polar's PKCE-capable endpoint.
    var authorizationURL: URL {
        URL(staticString: "https://auth.polar.com/oauth/authorize")
    }

    /// OAuth2 token endpoint (code exchange + refresh).
    var tokenURL: URL {
        URL(staticString: "https://auth.polar.com/oauth/token")
    }

    /// AccessLink REST base. `PolarConnector` targets the v3 `exercises`
    /// resource, whose response schema is stable and documented; migrating to
    /// the v4 `training-sessions` resource is tracked as an open point in
    /// ADR-11.
    var accessLinkBaseURL: URL {
        URL(staticString: "https://www.polaraccesslink.com/v3")
    }

    init(clientID: String, redirectURI: String, clientSecret: String? = nil) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.clientSecret = clientSecret
    }

    /// Loads the team's `clientID`/`redirectURI`/`clientSecret` from
    /// `PolarTeamConfig.plist` (issue #155) — the gitignored copy of
    /// `PolarTeamConfig.plist.example` every developer fills in locally with
    /// the credentials registered at <https://admin.polaraccesslink.com>.
    /// `bundle` defaults to the bundle containing this type, i.e. the app
    /// bundle at runtime.
    ///
    /// `PolarClientSecret` is read leniently — missing or still `REPLACE_ME`
    /// yields `nil` rather than throwing, unlike the other two keys. That
    /// keeps a config with only `clientID`/`redirectURI` loadable for the
    /// parts of the app that do not reach the token endpoint; it does not mean
    /// a real connection works without it (see this type's doc comment).
    static func loadFromTeamConfig(bundle: Bundle = Bundle(for: PolarConnector.self)) throws -> PolarClientConfiguration {
        guard let url = bundle.url(forResource: "PolarTeamConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
            throw PolarTeamConfigError.missingConfigFile
        }

        func value(for key: String) throws -> String {
            guard let value = raw[key], value != "REPLACE_ME" else {
                throw PolarTeamConfigError.placeholderNotReplaced(key: key)
            }
            return value
        }

        return PolarClientConfiguration(
            clientID: try value(for: "PolarClientID"),
            redirectURI: try value(for: "PolarRedirectURI"),
            clientSecret: try? value(for: "PolarClientSecret")
        )
    }
}
