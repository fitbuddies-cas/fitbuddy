import Foundation

/// Counts the "Helpful" / "Not helpful" taps locally (US-3 AC9, #32).
///
/// The verdict itself lives with the recommendation it was given for, in the
/// SwiftData row (#117): with a history on screen, a single last-verdict key
/// could no longer say which text it belonged to. What stays here is the
/// tally, which is about the PoC and not about any one analysis.
///
/// `UserDefaults`, like `AnalysisRateLimitStore`: two counters are scalars, and
/// putting them in the SwiftData cache would tie them to a store that is wiped
/// on every hard logout (ADR-001).
///
/// Write-only from the app's point of view: nothing reads the tally back into
/// the UI. It exists so the PoC evaluation can tell whether the
/// recommendations landed at all, without a single byte leaving the device.
actor AnalysisFeedbackStore {
    private static let tallyKey = "fitbuddy.analysis.feedback.tally"

    private let defaults: UserDefaults

    /// - Parameter defaults: Injectable for tests (isolated suite).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Counts one tap. A user changing their mind on the same recommendation
    /// counts twice here, because both taps happened — the row holding the
    /// verdict is what replaces one opinion with the other.
    func record(_ feedback: AnalysisFeedback) {
        var tally = storedTally()
        tally[feedback.rawValue, default: 0] += 1
        defaults.set(tally, forKey: Self.tallyKey)
    }

    /// How many times `feedback` has been given on this device.
    func count(of feedback: AnalysisFeedback) -> Int {
        storedTally()[feedback.rawValue] ?? 0
    }

    /// Drops everything recorded ("delete my data").
    func clear() {
        defaults.removeObject(forKey: Self.tallyKey)
    }

    /// `UserDefaults` hands back `[String: Any]`, so the counts are read
    /// defensively: a foreign or corrupted value restarts the tally instead of
    /// trapping on a bad cast.
    private func storedTally() -> [String: Int] {
        defaults.dictionary(forKey: Self.tallyKey)?.compactMapValues { $0 as? Int } ?? [:]
    }
}
