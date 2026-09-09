import Foundation

/// Failures of `ConnectorRegistry` itself, as opposed to `ConnectorError`,
/// which is what a provider reports. Kept separate so the provider contract
/// from ADR-6 does not grow cases that no connector can ever throw.
enum ConnectorRegistryError: Error, Equatable, Sendable {
    /// A call named a source that was never registered — a wiring mistake, not
    /// a runtime condition the user can recover from.
    case notRegistered(ConnectorSource)
}
