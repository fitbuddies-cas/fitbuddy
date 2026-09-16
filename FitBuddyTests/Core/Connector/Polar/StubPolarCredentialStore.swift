import Foundation
@testable import FitBuddy

/// In-memory `PolarCredentialStoring` that can be told to fail on demand —
/// the real store cannot be made to fail selectively on the simulator. Records
/// what was written so a test can assert on the calls, not just the outcome.
actor StubPolarCredentialStore: PolarCredentialStoring {
    enum Failure: Error {
        case injected
    }

    private(set) var storedCredentials: ConnectorCredentials?
    private(set) var storedMemberID: String?
    private(set) var savedTokenPairs: [(accessToken: String, refreshToken: String, expiresAt: Date)] = []
    private(set) var clearCount = 0

    var failWrites = false

    init(credentials: ConnectorCredentials? = nil, memberID: String? = nil) {
        storedCredentials = credentials
        storedMemberID = memberID
    }

    func setFailWrites(_ fail: Bool) { failWrites = fail }

    func credentials() throws -> ConnectorCredentials? {
        storedCredentials
    }

    func saveTokens(accessToken: String, refreshToken: String, expiresAt: Date) throws {
        if failWrites { throw Failure.injected }
        savedTokenPairs.append((accessToken, refreshToken, expiresAt))
        storedCredentials = .oauth(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    func memberID() throws -> String? {
        storedMemberID
    }

    func saveMemberID(_ memberID: String) throws {
        if failWrites { throw Failure.injected }
        storedMemberID = memberID
    }

    func clear() throws {
        clearCount += 1
        if failWrites { throw Failure.injected }
        storedCredentials = nil
        storedMemberID = nil
    }
}
