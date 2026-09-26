import Foundation

/// Validates a user-provided Hevy API key with a minimal authenticated call:
/// `GET /v1/workouts?page=1&pageSize=1`. HTTP 200 means the key is accepted;
/// HTTP 401 means Hevy rejected it. Fetching real workout data is out of scope
/// here — that is `HevyConnector`'s job (#25, #34).
actor HevyKeyValidator: HevyKeyValidating {
    /// Smallest possible authenticated request against the workouts endpoint.
    private static let probeURL = URL(staticString: "https://api.hevyapp.com/v1/workouts?page=1&pageSize=1")

    private let session: URLSession

    /// - Parameter session: Injectable for tests (e.g. with a stub
    ///   `URLProtocol`); defaults to the ephemeral `.fitBuddy` session so the
    ///   key-bearing request is never cached to disk.
    init(session: URLSession = .fitBuddy) {
        self.session = session
    }

    func validate(_ apiKey: String) async throws {
        var request = URLRequest(url: Self.probeURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.timeoutInterval = 15

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            if error.isUntrustedConnection { throw HevyKeyValidationError.untrustedConnection }
            throw HevyKeyValidationError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw HevyKeyValidationError.transport
        }
        switch http.statusCode {
        case 200:
            return
        case 401:
            throw HevyKeyValidationError.invalidKey
        default:
            // 403 deliberately lands here: Hevy uses 401 for a bad key, while
            // 403 can hit a valid key too (WAF, geo, quota) — telling the user
            // to regenerate the key would be wrong advice.
            throw HevyKeyValidationError.unexpectedStatus(http.statusCode)
        }
    }
}
