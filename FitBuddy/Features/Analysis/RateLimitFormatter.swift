import Foundation

/// Formats the remaining lock between two analyses — the «New analysis
/// available in 45s» label (US-3, #117).
///
/// Seconds, not hours: the lock is 60s long (`AnalysisRateLimitStore`), and a
/// minute-granular label could never count one down — it would print "1m"
/// until the whole window had passed.
///
/// Hand-rolled for the same reason as `SyncTimeFormatter`: the wording is
/// fixed by the requirement, and the output is English by policy, so there is
/// no locale to negotiate.
enum RateLimitFormatter {
    /// `"45s"`, `"1s"`. `nil` once the lock has lifted, so the caller drops the
    /// label instead of showing "0s".
    ///
    /// Rounded up, never down: with half a second left, "0s" would read as a
    /// countdown that finished while the button is still disabled.
    static func remaining(until availableAt: Date, now: Date) -> String? {
        let seconds = availableAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return "\(Int(seconds.rounded(.up)))s"
    }

    /// The full line under the analysis button: `"New analysis available in
    /// 45s"`, or `nil` when an analysis may run now.
    static func message(until availableAt: Date?, now: Date) -> String? {
        guard let availableAt, let remaining = remaining(until: availableAt, now: now) else { return nil }
        return "New analysis available in \(remaining)"
    }
}
