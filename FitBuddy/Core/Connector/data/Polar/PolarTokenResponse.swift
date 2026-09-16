import Foundation

/// Body of a successful Polar `POST /oauth/token` response (ADR-11), for both
/// the authorization-code exchange and the refresh call.
///
/// Only `access_token` is strictly required. AccessLink v3 sends no
/// `refresh_token` and an `expires_in` of about a year; a missing lifetime is
/// defaulted to that year rather than failing the whole connect flow.
struct PolarTokenResponse: Decodable, Equatable, Sendable {
    /// Lifetime assumed when `expires_in` is missing: the value AccessLink v3
    /// documents for its access tokens ("about one year").
    static let defaultLifetimeSeconds = 31_535_999

    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    /// Polar's own user id, echoed on the token response. Not currently
    /// persisted — FitBuddy identifies the user to AccessLink by its own
    /// `member-id` — but decoded so it is visible in logs during bring-up.
    let userID: Int?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case userID = "x_user_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn) ?? Self.defaultLifetimeSeconds
        userID = try container.decodeIfPresent(Int.self, forKey: .userID)
    }

    /// Folds the response into `ConnectorCredentials`, carrying `previousRefresh`
    /// forward when the response did not include a new refresh token.
    func credentials(now: Date, previousRefresh: String?) -> ConnectorCredentials {
        .oauth(
            accessToken: accessToken,
            refreshToken: refreshToken ?? previousRefresh ?? "",
            expiresAt: now.addingTimeInterval(TimeInterval(expiresIn))
        )
    }
}
