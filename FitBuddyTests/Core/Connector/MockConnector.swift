import Foundation
@testable import FitBuddy

/// Configurable `FitnessConnector` test double (ADR-6): canned responses for
/// `connect`/`validate`/`fetchActivities`, including error injection, so
/// connector-dependent code can be unit-tested without a real network call.
actor MockConnector: FitnessConnector {
    private var connectResult: Result<Void, ConnectorError> = .success(())
    private var validateResult: Result<Bool, ConnectorError> = .success(true)
    private var fetchActivitiesResult: Result<[Activity], ConnectorError> = .success([])

    /// Credentials of the last *successful* `connect`. A rejected attempt
    /// leaves this untouched, so a test can assert nothing stayed behind —
    /// see `lastAttemptedCredentials` for what was passed in regardless.
    private(set) var lastConnectedCredentials: ConnectorCredentials?
    private(set) var lastAttemptedCredentials: ConnectorCredentials?
    /// Cut-off the caller last asked for — the part a delta sync (#34) has to
    /// prove it gets right.
    private(set) var lastFetchSince: Date?
    private(set) var connectCallCount = 0
    private(set) var validateCallCount = 0
    private(set) var fetchActivitiesCallCount = 0
    private(set) var didDisconnect = false

    // MARK: - Configuration (called by tests before exercising the connector)

    func setConnectResult(_ result: Result<Void, ConnectorError>) {
        connectResult = result
    }

    func setValidateResult(_ result: Result<Bool, ConnectorError>) {
        validateResult = result
    }

    func setFetchActivitiesResult(_ result: Result<[Activity], ConnectorError>) {
        fetchActivitiesResult = result
    }

    /// Clears the recorded calls, keeping the configured responses — for
    /// tests that exercise the same connector across several rounds (retry,
    /// re-sync).
    func resetRecordedCalls() {
        lastConnectedCredentials = nil
        lastAttemptedCredentials = nil
        lastFetchSince = nil
        connectCallCount = 0
        validateCallCount = 0
        fetchActivitiesCallCount = 0
        didDisconnect = false
    }

    // MARK: - FitnessConnector

    func connect(credentials: ConnectorCredentials) async throws {
        connectCallCount += 1
        lastAttemptedCredentials = credentials
        if case .failure(let error) = connectResult { throw error }
        lastConnectedCredentials = credentials
    }

    func validate() async throws -> Bool {
        validateCallCount += 1
        return try validateResult.get()
    }

    /// Honours `since` the way the contract requires — the configured
    /// activities are filtered instead of returned wholesale, so a caller
    /// that asks for the wrong window sees it in its assertions.
    func fetchActivities(since: Date) async throws -> [Activity] {
        fetchActivitiesCallCount += 1
        lastFetchSince = since
        return try fetchActivitiesResult.get().filter { $0.startTime >= since }
    }

    func disconnect() async {
        didDisconnect = true
    }
}
