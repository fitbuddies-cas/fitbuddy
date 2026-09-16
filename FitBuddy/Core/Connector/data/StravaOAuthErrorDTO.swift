import Foundation

/// Wire shape of the error document Strava returns with a 400 or 401 from the
/// token endpoint:
///
/// ```json
/// {"message":"Bad Request","errors":[{"resource":"Application","field":"client_secret","code":"invalid"}]}
/// ```
///
/// Only `field` is read. It is what separates "your client secret is wrong"
/// (go to the credentials screen) from "your refresh token was revoked"
/// (reconnect) — the status code alone is the same for both.
struct StravaOAuthErrorDTO: Decodable, Equatable, Sendable {
    struct Entry: Decodable, Equatable, Sendable {
        let field: String?
    }

    let errors: [Entry]?

    /// Whether any entry blames the client ID or secret.
    var blamesClientCredentials: Bool {
        errors?.contains { $0.field == "client_id" || $0.field == "client_secret" } ?? false
    }
}
