import Foundation
@testable import FitBuddy

/// Configurable `StravaOAuthorizing` double recording every call.
///
/// Neither operation reaches a browser or the network here: `authorize` and
/// `refresh` each hand back whatever the test configured, so the connector
/// and the connection view model can be driven through every outcome.
actor StubStravaOAuthorizer: StravaOAuthorizing {
    private(set) var authorizeCalls: [StravaClientCredentials] = []
    private(set) var refreshCalls: [(client: StravaClientCredentials, refreshToken: String)] = []

    private var authorizeResult: Result<ConnectorCredentials, Error>
    private var refreshResult: Result<ConnectorCredentials, Error>

    init(
        authorizeResult: Result<ConnectorCredentials, Error> = .failure(StravaOAuthError.transport),
        refreshResult: Result<ConnectorCredentials, Error> = .failure(StravaOAuthError.transport)
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

    func authorize(_ credentials: StravaClientCredentials) async throws -> ConnectorCredentials {
        authorizeCalls.append(credentials)
        return try authorizeResult.get()
    }

    func refresh(_ credentials: StravaClientCredentials, refreshToken: String) async throws -> ConnectorCredentials {
        refreshCalls.append((credentials, refreshToken))
        return try refreshResult.get()
    }
}
