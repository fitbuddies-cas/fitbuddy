import Foundation

/// Abstraction over Hevy API-key validation so view models can be tested
/// without network access.
protocol HevyKeyValidating: Sendable {
    /// Checks `apiKey` against the Hevy API. Returns normally when the key is
    /// accepted; throws `HevyKeyValidationError` otherwise.
    func validate(_ apiKey: String) async throws
}
