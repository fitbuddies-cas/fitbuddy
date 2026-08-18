import Foundation

extension KeyedDecodingContainer {
    /// Decodes a whole-number field that Hevy types as `number`.
    ///
    /// A JSON `number` may arrive as `10` or `10.0`; plain `Int` decoding
    /// rejects the latter. Falling back to `Double` keeps a serialization
    /// detail from failing an otherwise valid workout.
    ///
    /// A value outside `Int`'s range yields nil rather than a trap: this helper
    /// exists to survive odd Hevy payloads, so an absurd number must degrade to
    /// a missing field, not crash the app.
    func decodeLooseIntIfPresent(forKey key: K) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        guard let double = try decodeIfPresent(Double.self, forKey: key) else { return nil }
        return Int(exactly: double.rounded())
    }
}
