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
/// `clientSecret` is optional on purpose. A registered *public* client (the
/// mobile case) authenticates the token request with PKCE and no secret; a
/// *confidential* client sends HTTP Basic `clientID:clientSecret`. FitBuddy is
/// a public client, so the secret stays `nil` — the field exists only so the
/// same type covers a future backend-assisted flow without a redesign.
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

    /// Loads the team's `clientID`/`redirectURI` from `PolarTeamConfig.plist`
    /// (issue #155) — the gitignored copy of `PolarTeamConfig.plist.example`
    /// every developer fills in locally with the credentials registered at
    /// <https://admin.polaraccesslink.com>. `bundle` defaults to the bundle
    /// containing this type, i.e. the app bundle at runtime.
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
            redirectURI: try value(for: "PolarRedirectURI")
        )
    }
}
