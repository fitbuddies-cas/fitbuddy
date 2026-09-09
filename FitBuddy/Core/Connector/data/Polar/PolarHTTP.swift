import Foundation

/// Shared HTTP helpers for the Polar OAuth and AccessLink calls, so both map
/// failures onto `ConnectorError` (ADR-6) the exact same way.
enum PolarHTTP {
    /// Performs `request` on `session` and returns the body plus the HTTP
    /// response, translating transport failures into `ConnectorError`.
    ///
    /// A cancelled request (the user left the screen, a newer sync superseded
    /// this one) is rethrown untouched — it is not a connectivity problem and
    /// must not surface as `.networkUnavailable`.
    static func send(
        _ request: URLRequest,
        on session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error.isCancellation { throw error }
            throw ConnectorError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.networkUnavailable
        }
        return (data, http)
    }

    /// Maps a non-2xx status to `ConnectorError`. `204 No Content` is a
    /// success and never reaches here.
    ///
    /// `400`/`401` from the token endpoint both mean "these credentials will
    /// not work" (`invalid_grant` on an expired refresh token comes back as
    /// `400`), so both route to `.unauthorized` — the caller's response is the
    /// same: drop the tokens and send the user back through the Polar consent
    /// screen.
    static func failure(for http: HTTPURLResponse) -> ConnectorError {
        switch http.statusCode {
        case 400, 401, 403:
            return .unauthorized
        case 429:
            return .rateLimited(retryAfter: retryAfter(from: http))
        case 500...599:
            return .serviceUnavailable
        default:
            return .invalidResponse
        }
    }

    /// Reads `Retry-After` in its seconds form. Polar does not send the
    /// HTTP-date form for this endpoint.
    static func retryAfter(from http: HTTPURLResponse) -> TimeInterval? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(raw.trimmingCharacters(in: .whitespaces))
    }
}
