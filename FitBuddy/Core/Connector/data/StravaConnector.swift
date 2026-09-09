import Foundation

/// Placeholder for the second data source (#35, ADR-6). Every call throws
/// `ConnectorError.notImplemented` — the OAuth flow and the Strava-to-`Activity`
/// mapping are v1 work.
///
/// It exists in v0 to hold the contract still: a conforming type compiled
/// alongside `HevyConnector` means any change to `FitnessConnector` breaks the
/// build here instead of silently drifting until the real implementation
/// starts. It is also what gives `ConnectorRegistry` a second source to be
/// tested against.
///
/// Not to be confused with `MockConnector`, the configurable test double: this
/// one is shipped app code and can only fail.
actor StravaConnector: FitnessConnector {
    func connect(credentials: ConnectorCredentials) async throws {
        throw ConnectorError.notImplemented
    }

    func validate() async throws -> Bool {
        throw ConnectorError.notImplemented
    }

    func fetchActivities(since: Date) async throws -> [Activity] {
        throw ConnectorError.notImplemented
    }

    /// The one call that does not throw: `disconnect` promises the connector
    /// holds no credentials afterwards, and a stub that never accepted any
    /// already keeps that promise. Throwing would also break the contract's
    /// non-throwing signature.
    func disconnect() async {}
}
