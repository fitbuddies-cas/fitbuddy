import Foundation

/// Wire shape of Strava's `POST /oauth/token` response, for both the
/// `authorization_code` and the `refresh_token` grant.
///
/// The athlete summary Strava attaches to the code exchange is deliberately
/// not decoded: nothing in the app needs it, and leaving it out keeps the DTO
/// identical for both grants.
struct StravaTokenDTO: Decodable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    /// Unix seconds.
    let expiresAt: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }

    /// The pair as the connector contract expects it.
    func makeCredentials() -> ConnectorCredentials {
        .oauth(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt))
        )
    }
}
