import Foundation

/// Persists the user's LLM provider priority order to `UserDefaults`. Only the
/// order is stored — key material lives exclusively in the Keychain. The first
/// provider is tried first on an analysis call; the following ones are the
/// fallbacks when a provider fails or has no credit left.
struct LLMPriorityStore {
    /// `UserDefaults` key holding the ordered provider raw values.
    static let priorityOrderKey = "fitbuddy.llm.priorityOrder"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Stored order. Raw values this build does not know (e.g. written by a
    /// newer build with more providers) are dropped rather than failing.
    var order: [LLMProvider] {
        guard let raw = defaults.stringArray(forKey: Self.priorityOrderKey) else { return [] }
        return raw.compactMap(LLMProvider.init(rawValue:))
    }

    func save(_ order: [LLMProvider]) {
        defaults.set(order.map(\.rawValue), forKey: Self.priorityOrderKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.priorityOrderKey)
    }
}
