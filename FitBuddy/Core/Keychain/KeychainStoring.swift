import Foundation

/// Abstraction over the Keychain so view models can be tested against a
/// failing store — the real `KeychainService` cannot be made to fail on
/// demand on the simulator.
protocol KeychainStoring: Sendable {
    func save(_ value: String, for key: KeychainKey) async throws
    func read(_ key: KeychainKey) async throws -> String?
    func delete(_ key: KeychainKey) async throws
    func exists(_ key: KeychainKey) async throws -> Bool
}

extension KeychainService: KeychainStoring {}
