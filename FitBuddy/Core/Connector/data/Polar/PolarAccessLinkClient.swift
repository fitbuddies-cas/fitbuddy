import Foundation
import OSLog

/// Thin wrapper around the Polar AccessLink REST resources `PolarConnector`
/// needs (ADR-11): registering the user once, then listing their exercises.
///
/// Split out from `PolarConnector` so the connector's orchestration (token
/// refresh, windowing, mapping) and the raw HTTP are tested separately.
actor PolarAccessLinkClient {
    private let baseURL: URL
    private let session: URLSession
    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "PolarAccessLinkClient")

    init(baseURL: URL = PolarClientConfiguration.accessLinkBaseURL, session: URLSession = .fitBuddy) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Registers the user with AccessLink under FitBuddy's own `memberID`.
    ///
    /// Idempotent from the caller's view: Polar answers `409 Conflict` when the
    /// member is already registered, which is treated as success — there is
    /// nothing to do and it is not an error.
    func registerUser(memberID: String, accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("users"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["member-id": memberID])

        let (_, http) = try await PolarHTTP.send(request, on: session)
        switch http.statusCode {
        case 200...299, 409:
            return
        default:
            logger.error("User registration returned \(http.statusCode, privacy: .public)")
            throw PolarHTTP.failure(for: http)
        }
    }

    /// Lists the user's available exercises. Polar keeps a rolling window
    /// (roughly the most recent sessions), so the caller still filters by the
    /// requested `since`. `204 No Content` means the list is empty.
    func exercises(accessToken: String) async throws -> [PolarExerciseDTO] {
        var request = URLRequest(url: baseURL.appendingPathComponent("exercises"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http) = try await PolarHTTP.send(request, on: session)
        switch http.statusCode {
        case 204:
            return []
        case 200...299:
            break
        default:
            logger.error("Exercise list returned \(http.statusCode, privacy: .public)")
            throw PolarHTTP.failure(for: http)
        }

        do {
            return try JSONDecoder().decode([PolarExerciseDTO].self, from: data)
        } catch {
            logger.error("Exercise list could not be decoded: \(error, privacy: .public)")
            throw ConnectorError.invalidResponse
        }
    }
}
