import Foundation

/// Source-agnostic contract for a fitness-data provider (ADR-6). The
/// dashboard and AI analysis depend only on this protocol and on `Activity`
/// — never on a provider-specific type — so a second source (`StravaConnector`,
/// #35) is a new conforming type, not a refactor of those layers.
///
/// - Note: The ADR's illustrative signature has `disconnect()` synchronous;
///   it is `async` here because every conformer is expected to be an `actor`
///   (matching `HevyKeyValidator`/`KeychainService`), and an actor can only
///   satisfy a protocol requirement from outside its isolation if that
///   requirement is itself async.
protocol FitnessConnector: Sendable {
    /// Stores the credentials for subsequent calls. Does not itself verify
    /// them — call `validate()` for that.
    func connect(credentials: ConnectorCredentials) async throws

    /// Pings the provider to confirm the stored credentials still work.
    /// - Returns: `true` if valid, `false` if the provider explicitly
    ///   rejected them; throws `ConnectorError` for anything that isn't a
    ///   clear yes/no (network down, rate limited, ...).
    func validate() async throws -> Bool

    /// All activities the provider has recorded since `since`, paginated
    /// internally — the caller always gets back one flat, normalized list.
    func fetchActivities(since: Date) async throws -> [Activity]

    /// Drops the in-memory credentials. Does not touch the Keychain — that
    /// stays the caller's responsibility — `WorkoutSyncService` owns it.
    func disconnect() async
}
