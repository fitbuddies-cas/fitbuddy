import Foundation
@testable import FitBuddy

/// Configurable `PolarOAuthorizing` double recording every call.
///
/// `authorize` hands back whatever the test configured, so the connection
/// view model can be driven through every outcome without a browser or the
/// network. Mirrors `StubStravaOAuthorizer`.
actor StubPolarOAuthorizer: PolarOAuthorizing {
    private(set) var authorizeCallCount = 0
    private(set) var refreshCallCount = 0
    private(set) var lastRefreshToken: String?

    private var authorizeResult: Result<ConnectorCredentials, Error>
    private var refreshResult: Result<ConnectorCredentials, Error>

    init(
        authorizeResult: Result<ConnectorCredentials, Error> = .failure(PolarOAuthError.cancelled),
        refreshResult: Result<ConnectorCredentials, Error> = .failure(ConnectorError.unauthorized)
    ) {
        self.authorizeResult = authorizeResult
        self.refreshResult = refreshResult
    }

    func setAuthorizeResult(_ result: Result<ConnectorCredentials, Error>) {
        authorizeResult = result
    }

    func setRefreshResult(_ result: Result<ConnectorCredentials, Error>) {
        refreshResult = result
    }

    func authorize(_ credentials: PolarClientCredentials) async throws -> ConnectorCredentials {
        authorizeCallCount += 1
        return try authorizeResult.get()
    }

    func refresh(_ credentials: PolarClientCredentials, refreshToken: String) async throws -> ConnectorCredentials {
        refreshCallCount += 1
        lastRefreshToken = refreshToken
        return try refreshResult.get()
    }
}
