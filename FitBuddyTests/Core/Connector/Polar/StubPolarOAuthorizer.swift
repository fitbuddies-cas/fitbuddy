import Foundation
@testable import FitBuddy

/// Configurable `PolarOAuthorizing` double recording every call.
///
/// `authorize` hands back whatever the test configured, so the connection
/// view model can be driven through every outcome without a browser or the
/// network.
actor StubPolarOAuthorizer: PolarOAuthorizing {
    private(set) var authorizeCallCount = 0

    private var authorizeResult: Result<ConnectorCredentials, Error>

    init(authorizeResult: Result<ConnectorCredentials, Error> = .failure(PolarOAuthError.cancelled)) {
        self.authorizeResult = authorizeResult
    }

    func setAuthorizeResult(_ result: Result<ConnectorCredentials, Error>) {
        authorizeResult = result
    }

    func authorize() async throws -> ConnectorCredentials {
        authorizeCallCount += 1
        return try authorizeResult.get()
    }
}
