import Foundation

/// Stores the "Helpful" / "Not helpful" taps locally (US-3 AC9, #32).
///
/// `UserDefaults`, like `AnalysisCooldownStore`: a verdict and two counters are
/// scalars, and putting them in the SwiftData cache would tie them to a store
/// that is wiped on every hard logout (ADR-001).
///
/// Only the last verdict is read back, and only to re-select a button on a
/// restored recommendation (#97). The tally is write-only from the app's point
/// of view: it exists so the PoC evaluation can tell whether the
/// recommendations landed at all, without a single byte leaving the device.
actor AnalysisFeedbackStore {
    private static let lastVerdictKey = "fitbuddy.analysis.feedback.lastVerdict"
    private static let lastTimestampKey = "fitbuddy.analysis.feedback.lastTimestamp"
    private static let tallyKey = "fitbuddy.analysis.feedback.tally"

    private let defaults: UserDefaults

    /// - Parameter defaults: Injectable for tests (isolated suite).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records one tap. Overwrites the last verdict — a user changing their
    /// mind on the same recommendation replaces it rather than adding a second
    /// opinion — but both taps count in the tally, because both happened.
    func record(_ feedback: AnalysisFeedback, at date: Date) {
        defaults.set(feedback.rawValue, forKey: Self.lastVerdictKey)
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastTimestampKey)
        var tally = storedTally()
        tally[feedback.rawValue, default: 0] += 1
        defaults.set(tally, forKey: Self.tallyKey)
    }

    /// The most recent verdict and when it was given, or `nil` if the user has
    /// never rated a recommendation.
    func lastFeedback() -> (feedback: AnalysisFeedback, date: Date)? {
        guard let raw = defaults.string(forKey: Self.lastVerdictKey),
              let feedback = AnalysisFeedback(rawValue: raw),
              defaults.object(forKey: Self.lastTimestampKey) != nil
        else { return nil }
        return (feedback, Date(timeIntervalSince1970: defaults.double(forKey: Self.lastTimestampKey)))
    }

    /// How many times `feedback` has been given on this device.
    func count(of feedback: AnalysisFeedback) -> Int {
        storedTally()[feedback.rawValue] ?? 0
    }

    /// Drops everything recorded ("delete my data").
    func clear() {
        defaults.removeObject(forKey: Self.lastVerdictKey)
        defaults.removeObject(forKey: Self.lastTimestampKey)
        defaults.removeObject(forKey: Self.tallyKey)
    }

    /// `UserDefaults` hands back `[String: Any]`, so the counts are read
    /// defensively: a foreign or corrupted value restarts the tally instead of
    /// trapping on a bad cast.
    private func storedTally() -> [String: Int] {
        defaults.dictionary(forKey: Self.tallyKey)?.compactMapValues { $0 as? Int } ?? [:]
    }
}
