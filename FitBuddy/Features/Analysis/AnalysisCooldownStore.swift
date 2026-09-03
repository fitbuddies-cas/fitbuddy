import Foundation

/// Persists the timestamp of the last analysis call, so the 6h cooldown
/// (US-3, #29) survives an app kill.
///
/// One window per analysis, whichever provider ends up answering it (#79):
/// `InferenceService` writes here once, when the first provider in the chain
/// accepts the request.
///
/// `UserDefaults`, not SwiftData, mirroring `SyncTimestampStore`: a single
/// scalar timestamp does not belong in the relational cache (ADR-001).
actor AnalysisCooldownStore {
    /// How long a user must wait between two analysis calls.
    static let duration: TimeInterval = 6 * 3600

    private static let lastCallKey = "fitbuddy.analysis.lastCallTimestamp"

    private let defaults: UserDefaults

    /// - Parameter defaults: Injectable for tests (isolated suite).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` if a call may proceed now; otherwise the instant the cooldown ends.
    func activeCooldown(now: Date) -> Date? {
        guard let last = lastCall() else { return nil }
        let availableAt = last.addingTimeInterval(Self.duration)
        return availableAt > now ? availableAt : nil
    }

    /// Timestamp of the last recorded call, or `nil` if none ever happened.
    func lastCall() -> Date? {
        guard defaults.object(forKey: Self.lastCallKey) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: Self.lastCallKey))
    }

    /// Records a call a provider accepted, starting a fresh cooldown window.
    func recordCall(at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastCallKey)
    }

    /// Drops the timestamp (hard logout, "delete my data").
    func clear() {
        defaults.removeObject(forKey: Self.lastCallKey)
    }
}
