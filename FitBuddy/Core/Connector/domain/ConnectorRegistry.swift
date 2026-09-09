import Foundation

/// Keeps the app's active `FitnessConnector`s in one place (#35, ADR-6) and
/// tracks, per source, whether its credentials are still usable.
///
/// Two jobs the individual connectors cannot do:
/// - **More than one source.** US-5 has Hevy and Strava side by side; without a
///   registry every caller would hold its own connector references and each new
///   source would touch all of them.
/// - **Expiry.** `ConnectorCredentials.oauth` carries an `expiresAt`, and only
///   whoever handed the credentials over sees it. The registry records it on a
///   successful `connect` and answers `state(of:)` / `sourcesNeedingRenewal()`
///   from it, which is what US-5 AC2's «Renew your Strava connection» prompt
///   reads.
///
/// An `actor` because connectors are actors themselves and callers reach this
/// from the main actor (dashboard) and from background sync alike.
///
/// v0 scope: no fan-out `fetchActivities` across all sources. The only real
/// connector is Hevy (#34) and `StravaConnector` throws `.notImplemented`, so
/// an aggregate fetch would have nothing to aggregate and one stub source would
/// fail the whole sync. Callers fetch through `connector(for:)`.
actor ConnectorRegistry {
    private var connectors: [ConnectorSource: any FitnessConnector] = [:]
    /// Sources whose `connect` succeeded and that have not been disconnected.
    private var connectedSources: Set<ConnectorSource> = []
    /// Credential expiry per connected source. Absent for schemes that do not
    /// expire — a Hevy API key is connected without ever appearing here.
    private var expiryDates: [ConnectorSource: Date] = [:]

    /// Sources with a connector registered, in `ConnectorSource.allCases`
    /// order so a UI list built from it does not reshuffle between reads.
    var registeredSources: [ConnectorSource] {
        ordered(connectors.keys)
    }

    // MARK: - Registration

    /// Adds a connector, replacing any connector already registered for that
    /// source. A replacement starts disconnected: the recorded credentials
    /// belonged to the connector that just went away.
    func register(_ connector: any FitnessConnector, for source: ConnectorSource) {
        connectors[source] = connector
        connectedSources.remove(source)
        expiryDates[source] = nil
    }

    /// Drops the connector for `source` after disconnecting it, so its
    /// credentials do not stay behind in an instance nobody holds any more.
    /// Removing a source that was never registered is a no-op.
    func unregister(_ source: ConnectorSource) async {
        await disconnect(source)
        connectors[source] = nil
    }

    /// The connector for `source`, for callers that need the provider itself
    /// (fetching activities) rather than its connection state.
    func connector(for source: ConnectorSource) -> (any FitnessConnector)? {
        connectors[source]
    }

    // MARK: - Connection lifecycle

    /// Hands `credentials` to the source's connector and, only if it accepts
    /// them, records the connection plus the expiry the credentials carry.
    /// A rejected attempt leaves the previous state untouched.
    /// - Throws: `ConnectorRegistryError.notRegistered` if no connector is
    ///   registered for `source`, or whatever the connector throws.
    func connect(_ source: ConnectorSource, credentials: ConnectorCredentials) async throws {
        let connector = try requireConnector(for: source)
        try await connector.connect(credentials: credentials)
        connectedSources.insert(source)
        expiryDates[source] = credentials.expiresAt
    }

    /// Asks the source's connector whether its credentials still work.
    /// - Throws: `ConnectorRegistryError.notRegistered`, or whatever the
    ///   connector throws.
    func validate(_ source: ConnectorSource) async throws -> Bool {
        try await requireConnector(for: source).validate()
    }

    /// Disconnects the source and forgets its recorded connection state.
    /// Not throwing and lenient about unknown sources: dropping a connection
    /// that is not there is the state the caller wanted anyway.
    func disconnect(_ source: ConnectorSource) async {
        await connectors[source]?.disconnect()
        connectedSources.remove(source)
        expiryDates[source] = nil
    }

    // MARK: - Expiry

    /// Connection state of a single source.
    /// - Parameter now: The instant to judge expiry against — injected so
    ///   tests do not have to wait for a token to run out.
    func state(of source: ConnectorSource, now: Date = .now) -> ConnectorConnectionState {
        guard connectedSources.contains(source) else { return .disconnected }
        guard let expiresAt = expiryDates[source] else { return .connected(expiresAt: nil) }
        // An expiry exactly at `now` is spent: the provider would reject the
        // very next request, so prompting is the honest answer.
        return expiresAt <= now ? .expired(since: expiresAt) : .connected(expiresAt: expiresAt)
    }

    /// Every connected source whose credentials have run out, in
    /// `ConnectorSource.allCases` order — the sources US-5 AC2 shows a
    /// `renewalPrompt` for.
    func sourcesNeedingRenewal(now: Date = .now) -> [ConnectorSource] {
        ordered(connectors.keys.filter { state(of: $0, now: now).needsRenewal })
    }

    // MARK: - Helpers

    private func requireConnector(for source: ConnectorSource) throws -> any FitnessConnector {
        guard let connector = connectors[source] else {
            throw ConnectorRegistryError.notRegistered(source)
        }
        return connector
    }

    private func ordered(_ sources: some Sequence<ConnectorSource>) -> [ConnectorSource] {
        let present = Set(sources)
        return ConnectorSource.allCases.filter(present.contains)
    }
}
