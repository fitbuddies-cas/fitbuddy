import Foundation
@testable import FitBuddy

/// In-memory `StravaCredentialStoring` that can be told to fail on demand —
/// the real store cannot be made to fail selectively on the simulator. Records
/// what was written so a test can assert on the calls, not just the outcome.
actor StubStravaCredentialStore: StravaCredentialStoring {
    enum Failure: Error {
        case injected
    }

    private(set) var storedClientCredentials: StravaClientCredentials?
    private(set) var storedCredentials: ConnectorCredentials?
    private(set) var savedTokenPairs: [(accessToken: String, refreshToken: String, expiresAt: Date)] = []
    private(set) var clearCount = 0
    private(set) var clearTokensCount = 0

    var failReads = false
    var failWrites = false

    init(
        clientCredentials: StravaClientCredentials? = nil,
        credentials: ConnectorCredentials? = nil
    ) {
        storedClientCredentials = clientCredentials
        storedCredentials = credentials
    }

    func setFailReads(_ fail: Bool) { failReads = fail }
    func setFailWrites(_ fail: Bool) { failWrites = fail }

    func clientCredentials() throws -> StravaClientCredentials? {
        if failReads { throw Failure.injected }
        return storedClientCredentials
    }

    func saveClientCredentials(_ credentials: StravaClientCredentials) throws {
        if failWrites { throw Failure.injected }
        storedClientCredentials = credentials
    }

    func credentials() throws -> ConnectorCredentials? {
        if failReads { throw Failure.injected }
        return storedCredentials
    }

    func saveTokens(accessToken: String, refreshToken: String, expiresAt: Date) throws {
        if failWrites { throw Failure.injected }
        savedTokenPairs.append((accessToken, refreshToken, expiresAt))
        storedCredentials = .oauth(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    func clearTokens() throws {
        clearTokensCount += 1
        if failWrites { throw Failure.injected }
        storedCredentials = nil
    }

    func clear() throws {
        clearCount += 1
        if failWrites { throw Failure.injected }
        storedClientCredentials = nil
        storedCredentials = nil
    }
}
