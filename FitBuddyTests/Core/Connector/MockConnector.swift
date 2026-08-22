import Foundation
@testable import FitBuddy

/// Configurable `FitnessConnector` test double (ADR-6): canned responses for
/// `connect`/`validate`/`fetchActivities`, including error injection, so
/// connector-dependent code can be unit-tested without a real network call.
actor MockConnector: FitnessConnector {
    private var connectResult: Result<Void, ConnectorError> = .success(())
    private var validateResult: Result<Bool, ConnectorError> = .success(true)
    private var fetchActivitiesResult: Result<[Activity], ConnectorError> = .success([])

    private(set) var lastConnectedCredentials: ConnectorCredentials?
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

    // MARK: - FitnessConnector

    func connect(credentials: ConnectorCredentials) async throws {
        lastConnectedCredentials = credentials
        if case .failure(let error) = connectResult { throw error }
    }

    func validate() async throws -> Bool {
        try validateResult.get()
    }

    func fetchActivities(since: Date) async throws -> [Activity] {
        try fetchActivitiesResult.get()
    }

    func disconnect() async {
        didDisconnect = true
    }
}
